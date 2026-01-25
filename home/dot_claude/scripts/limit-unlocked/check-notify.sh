#!/bin/bash
cd "$(dirname "$0")" || exit 1

TARGET_DIR="$HOME/.claude/projects"
CURRENT_TS=$(date +%s)

mkdir -p "$HOME/.claude/scripts/limit-unlocked/data"
PAST_FILE="$HOME/.claude/scripts/limit-unlocked/data/past.txt"
FUTURE_FILE="$HOME/.claude/scripts/limit-unlocked/data/future.txt"
NOTIFIED_FILE="$HOME/.claude/scripts/limit-unlocked/data/notified.txt"

source ./.env

> "$PAST_FILE"
> "$FUTURE_FILE"

find "$TARGET_DIR" -type f -name "*.jsonl" | while read -r file; do
    jq -c '
      select(
        .type == "assistant" and
        .message.type == "message" and
        (.message.content[0].text | type == "string") and
        (.message.content[0].text | startswith("Claude AI usage limit reached|"))
      ) |
      {
        cwd: .cwd,
        ts: (.message.content[0].text | split("|")[1] | tonumber)
      }
    ' "$file" | while read -r line; do
        cwd=$(echo "$line" | jq -r '.cwd')
        ts=$(echo "$line" | jq -r '.ts')

        if [ "$ts" -lt "$CURRENT_TS" ]; then
            echo -e "$cwd\t$ts" >> "$PAST_FILE"
        else
            echo -e "$cwd\t$ts" >> "$FUTURE_FILE"
        fi
    done
done

# 重複除去
sort -u "$PAST_FILE" -o "$PAST_FILE"
sort -u "$FUTURE_FILE" -o "$FUTURE_FILE"

echo "=== 過去のもの ==="
cat "$PAST_FILE"
echo "=== 未来のもの ==="
cat "$FUTURE_FILE"

# 初回実行確認
if [ ! -f "$NOTIFIED_FILE" ]; then
    cp "$PAST_FILE" "$NOTIFIED_FILE"
    exit 0
fi

send_to_claude_sessions() {
  for session in $(tmux list-sessions -F "#{session_name}"); do
    cmd=$(tmux display-message -t "$session" -p '#{pane_current_command}' 2>/dev/null || echo "unknown")
    if [[ "$cmd" == "claude" ]]; then
      echo "Sending keys to session $session"
      tmux send-keys -t "$session:0.0" "続けてください"
      sleep 1
      tmux send-keys -t "$session:0.0" Enter
      sleep 1
    fi
  done
}

# 未通知イベント検出
NEW_NOTIFICATIONS=$(grep -Fvxf "$NOTIFIED_FILE" "$PAST_FILE")
if [ -n "$NEW_NOTIFICATIONS" ]; then
    echo "=== 新しい過去イベント ==="
    echo "$NEW_NOTIFICATIONS"

    # Discord WebhookでEmbed通知
    while IFS=$'\t' read -r cwd ts; do
        TITLE="Claude Code のリミット解除"
        DESCRIPTION="${cwd} のリミットが経過し、再度利用可能になりました。"
        COLOR=5814783 # 青系色

        PAYLOAD=$(jq -n \
            --arg content "<@${MENTION_USER_ID}>" \
            --arg title "$TITLE" \
            --arg description "$DESCRIPTION" \
            --argjson color $COLOR \
            '{content: $content, embeds: [{title: $title, description: $description, color: $color}]}'
        )

        curl -s -H "Content-Type: application/json" \
             -X POST \
             -d "$PAYLOAD" \
             "$DISCORD_WEBHOOK_URL" >/dev/null
    done <<< "$NEW_NOTIFICATIONS"

    # tmuxセッションに通知
    send_to_claude_sessions

    # 通知済みファイル更新
    echo "$NEW_NOTIFICATIONS" >> "$NOTIFIED_FILE"
fi

