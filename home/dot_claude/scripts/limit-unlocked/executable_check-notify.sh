#!/bin/bash
# Claude Code のリミット到達・解除を、会話ログ (jsonl) に記録される構造化エラー情報から
# 検出し、Discord 通知とセッション再開を行う。
#
# tmux ペインの画面表示テキストを走査する方式は、Bash ツール実行中などに前面プロセスや
# 表示内容が一時的に切り替わることで誤検出（フラッピング）が起きるため採用しない。
# 代わりに、tmux セッションが起動している claude プロセスの pid から会話ログの
# jsonl ファイルを一意に特定し、その内容でリミット状態を判定する。
# tmux セッション名から、対応する claude プロセスの pid を特定する
resolve_claude_pid() {
    local session="$1" pane_pid

    # tmux はターゲットが "0" のような裸の数字だと、セッション名ではなく
    # 「未指定」とみなして現在アクティブなセッションへフォールバックしてしまう
    # ため、末尾に ":" を付けてセッション名指定であることを明示する
    pane_pid=$(tmux display-message -t "${session}:" -p '#{pane_pid}' 2>/dev/null) || return 1
    pgrep -P "$pane_pid" -f "^claude" | head -1
}

# claude プロセスの pid から、実際に sessions/<pid>.json が存在する
# CLAUDE_CONFIG_DIR を特定する（環境変数の生値ではなく、実際にヒットした
# ディレクトリを返す。空文字列を返すことはなく、見つからない場合は失敗を返す）
resolve_config_dir_for_pid() {
    local claude_pid="$1" config_dir dir
    [ -n "$claude_pid" ] || return 1

    config_dir=$(tr '\0' '\n' < "/proc/${claude_pid}/environ" 2>/dev/null | sed -n 's/^CLAUDE_CONFIG_DIR=//p')
    for dir in "$config_dir" "$HOME/.claude" "$HOME/.claude-work"; do
        [ -n "$dir" ] || continue
        if [ -f "$dir/sessions/${claude_pid}.json" ]; then
            echo "$dir"
            return 0
        fi
    done
    return 1
}

# tmux セッション名から、対応する claude プロセスが使用している
# CLAUDE_CONFIG_DIR を特定する（resolve_claude_pid + resolve_config_dir_for_pid の合成）
resolve_config_dir() {
    local session="$1" claude_pid
    claude_pid=$(resolve_claude_pid "$session") || return 1
    [ -n "$claude_pid" ] || return 1
    resolve_config_dir_for_pid "$claude_pid"
}

# config_dir の認証情報(.credentials.json)を使い、Claude Code の内部 API
# (/api/oauth/usage)を呼び出して現在の利用率を取得する。
# 標準出力: "<five_hour_utilization>\t<seven_day_utilization>"
# 取得できない場合(認証情報欠如・期限切れ・通信エラー・不正なレスポンス等)は
# 何も出力せず、終了コード1を返す。「解除」の誤判定を避けるため、
# 失敗時は必ず呼び出し元へ「取得不可」であることを伝える。
fetch_usage_status() {
    local config_dir="$1" creds access_token expires_at now_ms buffer_ms
    local response http_code body five_hour seven_day

    creds="$config_dir/.credentials.json"
    [ -f "$creds" ] || return 1

    access_token=$(jq -r '.claudeAiOauth.accessToken // empty' "$creds" 2>/dev/null)
    [ -n "$access_token" ] || return 1

    expires_at=$(jq -r '.claudeAiOauth.expiresAt // 0' "$creds" 2>/dev/null)
    now_ms=$(( $(date +%s) * 1000 ))
    buffer_ms=60000
    if [[ "$expires_at" =~ ^[0-9]+$ ]] && [ "$expires_at" -gt 0 ] && [ "$expires_at" -le $((now_ms + buffer_ms)) ]; then
        echo "fetch_usage_status: access token is expired or about to expire for $config_dir" >&2
        return 1
    fi

    response=$(curl -s --max-time 5 \
        -H "Authorization: Bearer ${access_token}" \
        -H "anthropic-beta: oauth-2025-04-20" \
        "https://api.anthropic.com/api/oauth/usage" -w '\n%{http_code}' 2>/dev/null)
    if [ -z "$response" ]; then
        echo "fetch_usage_status: curl request failed for $config_dir" >&2
        return 1
    fi

    http_code=$(echo "$response" | tail -1)
    body=$(echo "$response" | sed '$d')
    if [ "$http_code" != "200" ]; then
        echo "fetch_usage_status: unexpected HTTP status $http_code for $config_dir" >&2
        return 1
    fi

    five_hour=$(echo "$body" | jq -r '.five_hour.utilization // empty' 2>/dev/null)
    seven_day=$(echo "$body" | jq -r '.seven_day.utilization // empty' 2>/dev/null)
    if ! [[ "$five_hour" =~ ^[0-9]+(\.[0-9]+)?$ ]] || ! [[ "$seven_day" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        echo "fetch_usage_status: missing or non-numeric utilization in response for $config_dir" >&2
        return 1
    fi
    if ! awk -v v="$five_hour" 'BEGIN{exit !(v>=0 && v<=100)}' || ! awk -v v="$seven_day" 'BEGIN{exit !(v>=0 && v<=100)}'; then
        echo "fetch_usage_status: utilization out of range (0-100) in response for $config_dir" >&2
        return 1
    fi

    echo -e "${five_hour}\t${seven_day}"
}

# Usage API 照会のスロットリング状態を保持するファイルのパス
usage_last_checked_file() {
    echo "$HOME/.claude/scripts/limit-unlocked/data/usage_last_checked.txt"
}

# config_dir に対して直近30分以内にUsage APIを照会済みでないかを判定する。
# 許可する場合は終了コード0、スロットリング対象なら終了コード1を返す。
usage_check_allowed() {
    local config_dir="$1" file last_checked now
    file=$(usage_last_checked_file)
    [ -f "$file" ] || return 0
    last_checked=$(awk -F'\t' -v d="$config_dir" '$1 == d { print $2; exit }' "$file")
    [ -n "$last_checked" ] || return 0
    now=$(date +%s)
    [ $((now - last_checked)) -ge 1800 ]
}

# config_dir に対するUsage API照会の最終実行時刻を記録する。
# 成功・失敗に関わらず「試行した」時点で呼び出すことで、認証エラーや
# ネットワーク障害が続く間の連続リトライを防ぐ。
record_usage_checked() {
    local config_dir="$1" file tmp_file now
    file=$(usage_last_checked_file)
    mkdir -p "$(dirname "$file")"
    touch "$file"
    now=$(date +%s)
    tmp_file="${file}.tmp.$$"
    { awk -F'\t' -v d="$config_dir" '$1 != d { print }' "$file"; printf '%s\t%s\n' "$config_dir" "$now"; } > "$tmp_file"
    mv "$tmp_file" "$file"
}

# tmux セッション名から、対応する claude プロセスが書き込んでいる会話ログ (jsonl) の
# パスを特定する。claude は CLAUDE_CONFIG_DIR ごと（例: ~/.claude と ~/.claude-work）に
# sessions/<pid>.json（pid → sessionId の対応表）を別々に持つため両方を確認する。
# jsonl のパスは projects/<encoded-cwd>/<sessionId>.jsonl だが、cwd のエンコード規則
# （記号の置き換え方）は非公開かつ実装依存のため自前で再現せず、sessionId (UUID で一意)
# を find で直接検索することでエンコード方式のずれによる特定失敗を避ける。
resolve_jsonl_path() {
    local session="$1" claude_pid config_dir session_file session_id jsonl

    claude_pid=$(resolve_claude_pid "$session") || return 1
    [ -n "$claude_pid" ] || return 1

    config_dir=$(resolve_config_dir_for_pid "$claude_pid") || return 1
    session_file="$config_dir/sessions/${claude_pid}.json"

    session_id=$(jq -r '.sessionId // empty' "$session_file" 2>/dev/null)
    [ -n "$session_id" ] || return 1

    jsonl=$(find "$HOME/.claude/projects" -maxdepth 2 -name "${session_id}.jsonl" -print -quit 2>/dev/null)
    [ -n "$jsonl" ] || return 1
    echo "$jsonl"
}

# jsonl ファイルの直近の実メッセージ（assistant/user。system 等の内部イベントは無視する）を見て、
# リミット到達中かどうかと再開予定時刻(epoch)を判定する。
# 標準出力: "<is_limited:0|1>\t<reset_epoch>\t<reset_text>"
check_limit_status() {
    local jsonl="$1" last_msg is_err text ts reset_time tz reset_epoch msg_epoch fallback_seconds

    [ -f "$jsonl" ] || { echo -e "0\t-\t-"; return; }

    # jsonl は会話全体（数MB〜数十MBになりうる）だが直近の実メッセージが分かればよいため、
    # 末尾のみを走査対象にして cron の定期実行での毎回フルパースを避ける
    last_msg=$(tail -n 50 "$jsonl" | jq -c 'select(.type == "assistant" or .type == "user")' 2>/dev/null | tail -1)
    [ -n "$last_msg" ] || { echo -e "0\t-\t-"; return; }

    is_err=$(echo "$last_msg" | jq -r '((.isApiErrorMessage == true) and (.error == "rate_limit"))' 2>/dev/null)
    if [ "$is_err" != "true" ]; then
        echo -e "0\t-\t-"
        return
    fi

    text=$(echo "$last_msg" | jq -r '.message.content[0].text // ""' 2>/dev/null)
    ts=$(echo "$last_msg" | jq -r '.timestamp // ""' 2>/dev/null)
    msg_epoch=$(date -d "$ts" +%s 2>/dev/null)

    # text は会話ログ由来の自由形式文字列。タブ・改行を含み得るため、そのまま
    # 状態ファイル（タブ区切り 1 行 1 レコード）へ埋め込むとレコード構造が壊れる。
    # 通知文言としての可読性は保ったまま、区切り文字だけを空白に置き換える
    text=$(echo "$text" | tr '\t\n' '  ')

    # "11:30am" のような分あり表記と "3pm" のような分なし表記の両方に対応する
    reset_time=$(echo "$text" | grep -oiE '[0-9]{1,2}(:[0-9]{2})?[ap]m' | head -1)
    tz=$(echo "$text" | grep -oiE '\([^)]+\)' | head -1 | tr -d '()')
    reset_epoch=""
    if [ -n "$reset_time" ] && [ -n "$tz" ]; then
        reset_epoch=$(TZ="$tz" date -d "$reset_time" +%s 2>/dev/null)
        if [ -n "$msg_epoch" ] && [ -n "$reset_epoch" ] && [ "$reset_epoch" -le "$msg_epoch" ]; then
            # 指定時刻が既に過ぎている場合は翌日分を指しているとみなす
            reset_epoch=$(TZ="$tz" date -d "$reset_time tomorrow" +%s 2>/dev/null)
        fi
    fi

    if [ -z "$reset_epoch" ] && [ -n "$msg_epoch" ]; then
        # 文言からの時刻抽出に失敗した場合のフォールバック。
        # weekly limit は 7 日、session limit は 5 時間で再開されるのが通例
        if echo "$text" | grep -qi "weekly"; then
            fallback_seconds=$((7 * 24 * 3600)) # 7 日
        else
            fallback_seconds=$((5 * 3600)) # 5 時間
        fi
        reset_epoch=$((msg_epoch + fallback_seconds))
    fi

    echo -e "1\t${reset_epoch:--}\t${text}"
}

# 現在リミット中の tmux セッション一覧を検出し、$NEW_STATE_FILE に書き出す
detect_limited_sessions() {
    : > "$NEW_STATE_FILE"

    for session in $(tmux list-sessions -F "#{session_name}" 2>/dev/null); do
        local jsonl status_line is_limited reset_epoch reset_text cwd
        jsonl=$(resolve_jsonl_path "$session")
        if [ -z "$jsonl" ]; then
            # pgrep や /proc/<pid>/environ の読み取りは一時的に失敗しうる（他ツール実行中の
            # 前面プロセス切り替わり等）。特定失敗を「リミット解除」と誤認しないよう、
            # 前回記録があればそのまま引き継ぐ（本当にリミット中でなければ次回以降の
            # 検出で正しく除外される）
            awk -F'\t' -v s="$session" '$1 == s { print; exit }' "$STATE_FILE" >> "$NEW_STATE_FILE"
            continue
        fi

        status_line=$(check_limit_status "$jsonl")
        IFS=$'\t' read -r is_limited reset_epoch reset_text <<< "$status_line"
        [ "$is_limited" = "1" ] || continue

        cwd=$(tmux display-message -t "${session}:" -p '#{pane_current_path}' 2>/dev/null || echo "unknown")
        echo -e "${session}\t${cwd}\t${reset_epoch}\t${reset_text}" >> "$NEW_STATE_FILE"
    done

    sort -u "$NEW_STATE_FILE" -o "$NEW_STATE_FILE"
}

# reset_epoch (UTC の epoch 秒) を JST の可読文字列に変換する。
# 会話ログの文言はサービス側が UTC で埋め込むため、そのままでは日本語ユーザーには
# 分かりにくい。数値でない・空の場合は "-" を返す
format_jst() {
    local epoch="$1"
    [[ "$epoch" =~ ^[0-9]+$ ]] || { echo "-"; return; }
    TZ="Asia/Tokyo" date -d "@${epoch}" "+%Y-%m-%d %H:%M JST" 2>/dev/null || echo "-"
}

# Discord Embed 通知を送信する
send_discord() {
    local title="$1" description="$2" color="$3"
    local content=""
    [ -n "$MENTION_USER_ID" ] && content="<@${MENTION_USER_ID}>"

    local payload
    payload=$(jq -n \
        --arg content "$content" \
        --arg title "$title" \
        --arg description "$description" \
        --argjson color "$color" \
        '{content: $content, embeds: [{title: $title, description: $description, color: $color}]}'
    )

    curl -s -H "Content-Type: application/json" -X POST -d "$payload" "$DISCORD_WEBHOOK_URL" >/dev/null
}

# 指定した tmux セッションに再開キーを送る。
# ウィンドウ/ペイン番号を固定せずセッション名のみを指定し、tmux の base-index 設定
# （0 始まりとは限らない）に依存せず常にアクティブなウィンドウ・ペインへ送信する
#
# リミット到達時、 Claude Code は "What do you want to do?" という選択メニュー
# （"/rate-limit-options"）を自動的に開き、残ったままだと通常のテキスト入力が
# 効かなくなる既知の挙動があるため（詳細は anthropics/claude-code の Issue
# Tracker を参照）、ペイン内容にそのメニューが実際に出ている場合のみ Escape で
# 閉じてから再開メッセージを送る
resume_session() {
    local session="$1" pane_content

    # "0" のような裸の数字セッション名は tmux に「未指定」とみなされ
    # 現在のセッションへフォールバックしてしまうため、末尾に ":" を付けて
    # セッション名指定であることを明示する（display-message と同様の理由）
    pane_content=$(tmux capture-pane -t "${session}:" -p 2>/dev/null)
    if echo "$pane_content" | grep -q "What do you want to do"; then
        tmux send-keys -t "${session}:" Escape
        sleep 0.5
    fi

    tmux send-keys -t "${session}:" "<system-reminder>Claude Code's rate limit has been lifted. Continue the task you were working on before the interruption.</system-reminder>"
    sleep 1
    tmux send-keys -t "${session}:" Enter
}

# セッション名が対象ファイルに存在するか確認する
session_recorded_in() {
    local session="$1" file="$2"
    awk -F'\t' -v s="$session" '$1 == s { found=1 } END { exit !found }' "$file" 2>/dev/null
}

# メイン処理: このファイルが直接実行された場合のみ実行する。
# テスト等から source されたとき(BASH_SOURCE がスクリプト自身と一致しない)は
# 関数定義のみを提供し、mkdir・Discord通知・tmux操作などの副作用は起こさない。
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    cd "$(dirname "${BASH_SOURCE[0]}")" || exit 1

    mkdir -p "$HOME/.claude/scripts/limit-unlocked/data"
    STATE_FILE="$HOME/.claude/scripts/limit-unlocked/data/limited_sessions.txt"
    NEW_STATE_FILE="${STATE_FILE}.new"
    touch "$STATE_FILE"

    # shellcheck source=/dev/null
    source ./.env

    detect_limited_sessions
    now=$(date +%s)

    # 新規にリミットへ到達したセッションを通知する
    while IFS=$'\t' read -r session cwd reset_epoch reset_text; do
        [ -n "$session" ] || continue
        if ! session_recorded_in "$session" "$STATE_FILE"; then
            echo "Limit detected: $session ($cwd)"
            description="${cwd} (session: ${session}) が利用制限に達しました。"
            description="${description}"$'\n'"再開予定: $(format_jst "$reset_epoch")"
            [ -n "$reset_text" ] && [ "$reset_text" != "-" ] && description="${description}"$'\n'"${reset_text}"
            send_discord \
                "Claude Code のリミット到達" \
                "$description" \
                15158332 # 赤系色
        fi

        # 再開予定時刻を過ぎてもまだリミット中の場合は再開を試みる。
        # 再開に成功していれば、次回ポーリング時には会話ログの直近メッセージが
        # 送信した system-reminder 形式の再開メッセージに置き換わり、
        # is_limited が自然に 0 になるため、再開済みかどうかを別途記録しなくても二重送信にはならない
        if [[ "$reset_epoch" =~ ^[0-9]+$ ]] && [ "$now" -ge "$reset_epoch" ]; then
            echo "Resuming: $session ($cwd)"
            resume_session "$session"
        fi
    done < "$NEW_STATE_FILE"

    # リミットが解除された（前回は記録されていたが今回は検出されなかった）セッションを通知する
    while IFS=$'\t' read -r session cwd reset_epoch reset_text; do
        [ -n "$session" ] || continue
        session_recorded_in "$session" "$NEW_STATE_FILE" && continue # まだリミット中

        if tmux has-session -t "${session}:" 2>/dev/null; then
            echo "Limit unlocked: $session ($cwd)"
            send_discord \
                "Claude Code のリミット解除" \
                "${cwd} (session: ${session}) のリミットが解除されました。" \
                5814783 # 青系色
        fi
    done < "$STATE_FILE"

    mv "$NEW_STATE_FILE" "$STATE_FILE"
fi
