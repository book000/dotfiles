#!/bin/bash
# UserPromptSubmit フック: プロンプト送信時に最後の送信時刻を記録し、通知キャンセルフラグを作成

cd "$(dirname "$0")" || exit 0

# データディレクトリの作成
DATA_DIR="$HOME/.claude/scripts/completion-notify/data"
mkdir -p "$DATA_DIR"

# 入力 JSON を読み取る（使用しないが標準入力を消費する）
INPUT_JSON=$(cat)

# 現在時刻を Unix timestamp で記録
CURRENT_TIME=$(date +%s)
echo "$CURRENT_TIME" > "$DATA_DIR/last-prompt-time.txt"

# 通知キャンセルフラグを作成（既存の通知をキャンセル）
touch "$DATA_DIR/cancel-notify.flag"

exit 0
