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

# 入力 JSON を読み取る（使用しないが標準入力を消費する）
# shellcheck disable=SC2034
INPUT_JSON=$(cat)

# 現在時刻を Unix timestamp で記録
CURRENT_TIME=$(date +%s)
echo "$CURRENT_TIME" > "$DATA_DIR/last-prompt-time.txt"

# 通知キャンセルフラグを作成（既存の通知をキャンセル）
touch "$DATA_DIR/cancel-notify.flag"

exit 0
