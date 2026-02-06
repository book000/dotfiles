#!/bin/bash

# Claude Code UserPromptSubmit hook として動作するスクリプト
# UserPromptSubmit hook は以下の形式の JSON を標準入力から受け取る:
# {
#   "session_id": "string",
#   "transcript_path": "~/.claude/projects/.../session.jsonl",
#   "cwd": "string",
#   "permission_mode": "string",
#   "hook_event_name": "UserPromptSubmit"
# }

cd "$(dirname "$0")" || exit 1
# shellcheck source=/dev/null
source ./.env

# データディレクトリの作成
DATA_DIR="$HOME/.claude/scripts/completion-notify/data"
mkdir -p "$DATA_DIR"

# 入力 JSON を読み取り
# shellcheck disable=SC2034
INPUT_JSON=$(cat)

# セッション ID を取得
SESSION_ID=$(echo "$INPUT_JSON" | jq -r '.session_id // empty')

# 現在時刻を Unix timestamp で記録
CURRENT_TIME=$(date +%s)
echo "$CURRENT_TIME" > "$DATA_DIR/last-prompt-time.txt"

# 通知キャンセルフラグを作成（既存の通知をキャンセル）
touch "$DATA_DIR/cancel-notify.flag"

# idle_prompt のクールダウンをリセット（セッション ID に対応するファイルを削除）
if [[ -n "$SESSION_ID" ]]; then
  LAST_IDLE_NOTIFY_FILE="$DATA_DIR/last-idle-notify-${SESSION_ID}.txt"
  if [[ -f "$LAST_IDLE_NOTIFY_FILE" ]]; then
    rm -f "$LAST_IDLE_NOTIFY_FILE"
    echo "🔄 Reset idle_prompt cooldown for session: $SESSION_ID" >&2
  fi
fi

# 古い idle_prompt クールダウンファイルをクリーンアップ（7 日以上経過したファイル）
# find コマンドが利用可能な場合のみ実行
if command -v find >/dev/null 2>&1; then
  find "$DATA_DIR" -name "last-idle-notify-*.txt" -type f -mtime +7 -delete 2>/dev/null || true
fi

exit 0
