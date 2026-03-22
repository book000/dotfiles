#!/bin/bash
# tmux IPC メッセージ受信スクリプト
#
# inbox 内のメッセージをスキャンして処理し、processed/ へ移動する。
# TTL を超過したメッセージは破棄する。
#
# Usage: tmux-ipc-receive.sh [session_id]
#   session_id: 対象セッション ID。省略時は現在の tmux セッションを使用。
#
# 出力: 有効なメッセージが存在した場合、標準出力に内容を表示する

set -euo pipefail

IPC_DIR="/tmp/tmux-ipc"

# セッション ID を決定
if [[ -n "${1:-}" ]]; then
  SESSION_ID="$1"
elif [[ -n "${TMUX:-}" ]]; then
  TMUX_SESSION=$(tmux display-message -p '#S' 2>/dev/null || echo "")
  TMUX_PANE=$(tmux display-message -p '#{pane_id}' 2>/dev/null || echo "")
  SESSION_ID="${TMUX_SESSION}.${TMUX_PANE}"
else
  echo "Error: No session ID provided and not in a tmux session" >&2
  exit 1
fi

INBOX_DIR="$IPC_DIR/$SESSION_ID/inbox"
PROCESSED_DIR="$IPC_DIR/$SESSION_ID/processed"

if [[ ! -d "$INBOX_DIR" ]]; then
  echo "No inbox found for session: $SESSION_ID" >&2
  echo "Hint: Run 'tmux-ipc-register.sh' to register this session" >&2
  exit 0
fi

mkdir -p "$PROCESSED_DIR"

CURRENT_TIME=$(date +%s)
MSG_COUNT=0
EXPIRED_COUNT=0

# inbox 内の全メッセージを処理
shopt -s nullglob
for msg_file in "$INBOX_DIR"/*.json; do
  [[ -f "$msg_file" ]] || continue

  MSG_JSON=$(cat "$msg_file" 2>/dev/null) || continue

  # JSON フィールドを抽出
  MSG_ID=$(echo "$MSG_JSON" | jq -r '.id        // "unknown"')
  MSG_FROM=$(echo "$MSG_JSON" | jq -r '.from     // "unknown"')
  MSG_TIMESTAMP=$(echo "$MSG_JSON" | jq -r '.timestamp // 0')
  MSG_TTL=$(echo "$MSG_JSON" | jq -r '.ttl       // 300')
  MSG_BODY=$(echo "$MSG_JSON" | jq -r '.body     // ""')

  # TTL チェック
  EXPIRY=$((MSG_TIMESTAMP + MSG_TTL))
  if [[ "$CURRENT_TIME" -gt "$EXPIRY" ]]; then
    echo "[tmux-ipc] TTL expired: $MSG_ID (from: $MSG_FROM)" >&2
    mv "$msg_file" "$PROCESSED_DIR/" 2>/dev/null || rm -f "$msg_file"
    EXPIRED_COUNT=$((EXPIRED_COUNT + 1))
    continue
  fi

  # 有効なメッセージを出力
  MSG_COUNT=$((MSG_COUNT + 1))
  echo "--- [tmux-ipc] Message from ${MSG_FROM} (id: ${MSG_ID}) ---"
  echo "$MSG_BODY"
  echo ""

  # processed/ へ移動
  mv "$msg_file" "$PROCESSED_DIR/" 2>/dev/null || rm -f "$msg_file"
done
shopt -u nullglob

if [[ "$MSG_COUNT" -gt 0 ]]; then
  echo "[tmux-ipc] Processed ${MSG_COUNT} message(s) (${EXPIRED_COUNT} expired)"
else
  echo "[tmux-ipc] No new messages (${EXPIRED_COUNT} expired)"
fi
