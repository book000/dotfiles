#!/bin/bash
# バックグラウンド通知処理: 1 分待機後、条件を満たせば Discord に通知を送信

# 環境変数の読み込み
if [[ -f "$HOME/.env" ]]; then
    source "$HOME/.env"
fi

export DISCORD_WEBHOOK_URL="${DISCORD_CLAUDE_WEBHOOK:-}"
export MENTION_USER_ID="${DISCORD_CLAUDE_MENTION_USER_ID:-}"

# データディレクトリとファイルパス
DATA_DIR="$HOME/.claude/scripts/completion-notify/data"
CANCEL_FLAG="$DATA_DIR/cancel-notify.flag"
LAST_PROMPT_TIME_FILE="$DATA_DIR/last-prompt-time.txt"

# 標準入力からペイロードを受け取る
PAYLOAD=$(cat)

# 1 分待機
sleep 60

# キャンセルフラグのチェック
if [[ -f "$CANCEL_FLAG" ]]; then
    rm -f "$CANCEL_FLAG"
    exit 0
fi

# 最後のプロンプト送信時刻のチェック
if [[ -f "$LAST_PROMPT_TIME_FILE" ]]; then
    LAST_PROMPT_TIME=$(cat "$LAST_PROMPT_TIME_FILE" 2>/dev/null)
    if [[ "$LAST_PROMPT_TIME" =~ ^[0-9]+$ ]]; then
        CURRENT_TIME=$(date +%s)
        TIME_DIFF=$((CURRENT_TIME - LAST_PROMPT_TIME))

        # 60 秒未満の場合は通知をスキップ
        if [[ $TIME_DIFF -lt 60 ]]; then
            exit 0
        fi
    fi
fi

# Discord 通知の送信
webhook_url="${DISCORD_WEBHOOK_URL}"
if [[ -n "${webhook_url}" ]]; then
    curl -H "Content-Type: application/json" \
         -X POST \
         -d "${PAYLOAD}" \
         "${webhook_url}" 2>&1
fi

exit 0
