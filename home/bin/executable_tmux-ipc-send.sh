#!/bin/bash
# tmux IPC メッセージ送信スクリプト
#
# 指定した宛先セッションの inbox にメッセージを書き込み、必要に応じて
# tmux send-keys で受信側エージェントに通知する。
#
# Usage: tmux-ipc-send.sh <to_session_id> <body> [ttl_seconds]
#   to_session_id : 宛先セッション ID (例: main.%2)
#   body          : 送信するメッセージ本文
#   ttl_seconds   : メッセージの有効期限（秒）。省略時は 300 秒

set -euo pipefail

IPC_DIR="/tmp/tmux-ipc"
REGISTRY="$IPC_DIR/registry.json"

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <to_session_id> <body> [ttl_seconds]" >&2
  exit 1
fi

TO="$1"
BODY="$2"
TTL="${3:-300}"

# 送信元セッション ID を取得
if [[ -n "${TMUX:-}" ]]; then
  TMUX_SESSION=$(tmux display-message -p '#S' 2>/dev/null || echo "")
  TMUX_PANE=$(tmux display-message -p '#{pane_id}' 2>/dev/null || echo "")
  FROM="${TMUX_SESSION}.${TMUX_PANE}"
else
  FROM="external"
fi

# 宛先 inbox の存在確認
INBOX_DIR="$IPC_DIR/$TO/inbox"
if [[ ! -d "$INBOX_DIR" ]]; then
  echo "Error: Destination session not registered: $TO" >&2
  echo "Hint: Run 'tmux-ipc-register.sh' in the target session first" >&2
  exit 1
fi

# UUID 生成
if command -v uuidgen &>/dev/null; then
  MSG_ID=$(uuidgen | tr '[:upper:]' '[:lower:]')
elif [[ -f /proc/sys/kernel/random/uuid ]]; then
  MSG_ID=$(cat /proc/sys/kernel/random/uuid)
else
  # フォールバック: /dev/urandom から生成
  MSG_ID=$(od -x /dev/urandom | head -1 | awk '{OFS="-"; print $2$3,$4,$5,$6,$7$8$9}' | head -c 36)
fi

TIMESTAMP=$(date +%s)
MSG_FILE="$INBOX_DIR/${TIMESTAMP}-${MSG_ID}.json"

# メッセージを inbox に書き込み
jq -n \
  --arg     id        "$MSG_ID" \
  --arg     from      "$FROM" \
  --arg     to        "$TO" \
  --argjson timestamp "$TIMESTAMP" \
  --argjson ttl       "$TTL" \
  --arg     body      "$BODY" \
  '{"id": $id, "from": $from, "to": $to, "timestamp": $timestamp, "ttl": $ttl, "body": $body}' \
  > "$MSG_FILE"

echo "Sent: $MSG_ID -> $TO"

# 受信側への通知 (tmux send-keys)
# 宛先セッションのエージェント種別を確認
DEST_AGENT="unknown"
if [[ -f "$REGISTRY" ]]; then
  DEST_AGENT=$(jq -r --arg id "$TO" \
    '.sessions[] | select(.id == $id) | .agent // "unknown"' \
    "$REGISTRY" 2>/dev/null || echo "unknown")
fi

# tmux ターゲットを構築 (session_id = "session.pane" 形式)
TMUX_TARGET_SESSION="${TO%.*}"
TMUX_TARGET_PANE="${TO##*.}"

if tmux has-session -t "$TMUX_TARGET_SESSION" 2>/dev/null; then
  case "$DEST_AGENT" in
    claude)
      # Claude Code: UserPromptSubmit フックが inbox をスキャンするため追加通知は不要。
      : # 何もしない（フックに委ねる）
      ;;
    gemini | codex | copilot | unknown)
      # 非 Claude エージェント: 受信スクリプトを実行するよう通知
      NOTIFY_MSG="[tmux-ipc] New message from ${FROM}. Run: tmux-ipc-receive.sh"
      tmux send-keys -t "$TMUX_TARGET_PANE" \
        "$NOTIFY_MSG" 2>/dev/null || true
      sleep 3
      tmux send-keys -t "$TMUX_TARGET_PANE" \
        Enter 2>/dev/null || true
      ;;
  esac
fi
