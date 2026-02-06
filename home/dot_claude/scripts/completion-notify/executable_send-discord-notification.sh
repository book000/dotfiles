#!/bin/bash
# バックグラウンド通知処理: 1 分待機後、条件を満たせば Discord に通知を送信

cd "$(dirname "$0")" || exit 1
source ./.env

export DISCORD_WEBHOOK_URL="${DISCORD_CLAUDE_WEBHOOK:-}"
export MENTION_USER_ID="${DISCORD_CLAUDE_MENTION_USER_ID:-}"

# データディレクトリとファイルパス
DATA_DIR="$HOME/.claude/scripts/completion-notify/data"
CANCEL_FLAG="$DATA_DIR/cancel-notify.flag"
LAST_PROMPT_TIME_FILE="$DATA_DIR/last-prompt-time.txt"

# 標準入力からペイロードを受け取る
PAYLOAD=$(cat)

# この通知プロセスの開始時刻を記録（キャンセルフラグの検証に使用）
START_TIME=$(date +%s)

# 待機時間を環境変数から取得（デフォルト: 60 秒）
DELAY="${NOTIFICATION_DELAY:-60}"
if ! [[ "$DELAY" =~ ^[0-9]+$ ]] || [[ "$DELAY" -lt 0 ]]; then
  # 無効な値の場合はデフォルトを使用
  DELAY=60
fi

# キャンセル可能な待機ループ
ELAPSED=0
while [[ $ELAPSED -lt $DELAY ]]; do
    sleep 1
    ELAPSED=$((ELAPSED + 1))

    # キャンセルフラグのチェック
    if [[ -f "$CANCEL_FLAG" ]]; then
        # キャンセルフラグの更新時刻を取得し、このプロセス開始後に立ったキャンセルかを判定する
        CANCEL_MTIME=$(stat -c %Y "$CANCEL_FLAG" 2>/dev/null || stat -f %m "$CANCEL_FLAG" 2>/dev/null)

        if [[ "$CANCEL_MTIME" =~ ^[0-9]+$ ]]; then
            # フラグの更新時刻がこのプロセス開始時刻以降ならキャンセル扱いとする
            if (( CANCEL_MTIME >= START_TIME )); then
                # 他プロセスのためにフラグは削除しない
                exit 0
            fi
        else
            # stat で更新時刻が取得できない場合は、安全側に倒してキャンセル扱いとする
            exit 0
        fi
    fi

    # 最後のプロンプト送信時刻のチェック
    if [[ -f "$LAST_PROMPT_TIME_FILE" ]]; then
        LAST_PROMPT_TIME=$(cat "$LAST_PROMPT_TIME_FILE" 2>/dev/null)
        if [[ "$LAST_PROMPT_TIME" =~ ^[0-9]+$ ]]; then
            # LAST_PROMPT_TIME が START_TIME よりも新しい（ユーザーがプロンプトを送信した）場合はキャンセル
            if (( LAST_PROMPT_TIME > START_TIME )); then
                exit 0
            fi
        fi
    fi
done

# Discord 通知の送信
webhook_url="${DISCORD_WEBHOOK_URL}"
if [[ -n "${webhook_url}" ]]; then
    # ログファイルのパス（Webhook URL やペイロードは出力しない）
    LOG_FILE="${DATA_DIR}/discord-notify.log"
    mkdir -p "${DATA_DIR}" 2>/dev/null

    # curl 実行: レスポンスボディは破棄し、HTTP ステータスのみ取得
    http_status=$(curl -sS -o /dev/null -w "%{http_code}" \
        -H "Content-Type: application/json" \
        -X POST \
        -d "${PAYLOAD}" \
        "${webhook_url}" 2>>"${LOG_FILE}")
    curl_exit_code=$?

    # 送信失敗時のみログに記録（Webhook URL やペイロードは出力しない）
    if [[ ${curl_exit_code} -ne 0 || -z "${http_status}" || ${http_status} -lt 200 || ${http_status} -ge 300 ]]; then
        {
            printf '%s ' "$(date --iso-8601=seconds 2>/dev/null || date -Iseconds)"
            printf 'ERROR: Failed to send Discord notification (exit=%s, http_status=%s)\n' "${curl_exit_code}" "${http_status:-unknown}"
        } >>"${LOG_FILE}"
    fi
fi

exit 0
