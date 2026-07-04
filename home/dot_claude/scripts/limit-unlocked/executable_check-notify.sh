#!/bin/bash
# Claude Code のリミット到達・解除を tmux ペイン表示から検出し、Discord 通知とセッション再開を行う。
cd "$(dirname "$0")" || exit 1

mkdir -p "$HOME/.claude/scripts/limit-unlocked/data"
STATE_FILE="$HOME/.claude/scripts/limit-unlocked/data/limited_sessions.txt"
NEW_STATE_FILE="${STATE_FILE}.new"
touch "$STATE_FILE"

# shellcheck source=/dev/null
source ./.env

# Claude Code がリミット到達時にペインへ表示するバナー文言（セッション/ウィークリー両方、
# および過去バージョンの "usage limit reached" 形式にも対応する）
LIMIT_PATTERN="hit (your|its) (session|weekly) (usage )?limit|usage limit reached"

# 現在リミット中の tmux セッション一覧を検出し、$NEW_STATE_FILE に書き出す
detect_limited_sessions() {
    : > "$NEW_STATE_FILE"

    for session in $(tmux list-sessions -F "#{session_name}" 2>/dev/null); do
        cmd=$(tmux display-message -t "$session" -p '#{pane_current_command}' 2>/dev/null || echo "unknown")
        if [ "$cmd" != "claude" ]; then
            # Bash ツール実行中などは前面プロセスが一時的に claude 以外（bash 等）になる。
            # この瞬間だけを見て「解除された」と誤判定すると、resume_session が誤発火して
            # ユーザーの実ターミナルに誤ったキー入力を送ってしまうため、前回の記録があれば
            # そのまま引き継ぎ、確実に claude 表示へ戻ったタイミングで再判定する
            prev_line=$(awk -F'\t' -v s="$session" '$1 == s { print; exit }' "$STATE_FILE" 2>/dev/null)
            [ -n "$prev_line" ] && echo "$prev_line" >> "$NEW_STATE_FILE"
            continue
        fi

        cwd=$(tmux display-message -t "$session" -p '#{pane_current_path}' 2>/dev/null || echo "unknown")
        # -S を指定せず現在の可視画面のみを対象にする。スクロールバック履歴まで含めると、
        # 過去の調査出力などに含まれる文言を誤検出する（例: このバナー文言自体を出力したログ）
        pane_text=$(tmux capture-pane -t "$session" -p 2>/dev/null)

        if echo "$pane_text" | grep -qiE "$LIMIT_PATTERN"; then
            reset_info=$(echo "$pane_text" | grep -oiE "resets [0-9:]+[ap]m \([^)]+\)" | tail -1)
            echo -e "${session}\t${cwd}\t${reset_info}" >> "$NEW_STATE_FILE"
        fi
    done

    sort -u "$NEW_STATE_FILE" -o "$NEW_STATE_FILE"
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

# 指定した tmux セッションに再開キーを送る
resume_session() {
    local session="$1"
    # ウィンドウ/ペイン番号を固定せずセッション名のみを指定する。
    # tmux の base-index 設定（0 始まりとは限らない）に依存せず、
    # 常にそのセッションの現在アクティブなウィンドウ・ペインへ送信するため
    tmux send-keys -t "$session" "続けてください"
    sleep 1
    tmux send-keys -t "$session" Enter
}

# セッション名・作業ディレクトリの組み合わせが対象ファイルに存在するか確認する
session_recorded_in() {
    local session="$1" cwd="$2" file="$3"
    grep -qF "$(printf '%s\t%s' "$session" "$cwd")" "$file" 2>/dev/null
}

detect_limited_sessions

# 新規にリミットへ到達したセッションを通知する
while IFS=$'\t' read -r session cwd reset_info; do
    [ -n "$session" ] || continue
    if ! session_recorded_in "$session" "$cwd" "$STATE_FILE"; then
        echo "Limit detected: $session ($cwd)"
        description="${cwd} (session: ${session}) が利用制限に達しました。"
        [ -n "$reset_info" ] && description="${description}"$'\n'"${reset_info}"
        send_discord \
            "Claude Code のリミット到達" \
            "$description" \
            15158332 # 赤系色
    fi
done < "$NEW_STATE_FILE"

# リミットが解除された（前回は記録されていたが今回は検出されなかった）セッションを通知・再開する
while IFS=$'\t' read -r session cwd reset_info; do
    [ -n "$session" ] || continue
    session_recorded_in "$session" "$cwd" "$NEW_STATE_FILE" && continue # まだリミット中

    # tmux セッション自体が閉じられている場合は再開できないため通知のみスキップする
    if tmux has-session -t "$session" 2>/dev/null; then
        echo "Limit unlocked: $session ($cwd)"
        send_discord \
            "Claude Code のリミット解除" \
            "${cwd} (session: ${session}) のリミットが経過し、再度利用可能になりました。" \
            5814783 # 青系色
        resume_session "$session"
    fi
done < "$STATE_FILE"

mv "$NEW_STATE_FILE" "$STATE_FILE"
