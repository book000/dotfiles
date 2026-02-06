#!/bin/bash

# Claude Code PostToolUse hook として動作するスクリプト
# ツール使用後にキャンセルフラグを立て、待機中の通知をキャンセル

# データディレクトリの作成
DATA_DIR="$HOME/.claude/scripts/completion-notify/data"
mkdir -p "$DATA_DIR"

# 入力 JSON を読み取り
INPUT_JSON=$(cat)

# セッション ID とツール名を取得
SESSION_ID=$(echo "$INPUT_JSON" | jq -r '.session_id // empty')
TOOL_NAME=$(echo "$INPUT_JSON" | jq -r '.tool_name // empty')

# 通知キャンセルフラグを作成（既存の通知をキャンセル）
touch "$DATA_DIR/cancel-notify.flag"

# セッション固有のキャンセルフラグも作成（将来の拡張用）
if [[ -n "$SESSION_ID" ]]; then
  touch "$DATA_DIR/cancel-notify-${SESSION_ID}.flag"
fi

# AskUserQuestion の PostToolUse の場合、表示中フラグを削除
if [[ "$TOOL_NAME" == "AskUserQuestion" && -n "$SESSION_ID" ]]; then
  rm -f "$DATA_DIR/askuserquestion-active-${SESSION_ID}.flag" 2>/dev/null
fi

exit 0
