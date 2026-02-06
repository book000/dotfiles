#!/bin/bash

# Claude Code PreToolUse hook として動作するスクリプト
# AskUserQuestion ツール使用時に通知を送信する
# PreToolUse hook は以下の形式の JSON を標準入力から受け取る:
# {
#   "session_id": "string",
#   "transcript_path": "~/.claude/projects/.../session.jsonl",
#   "cwd": "string",
#   "permission_mode": "string",
#   "hook_event_name": "PreToolUse",
#   "tool_name": "AskUserQuestion",
#   "tool_input": {...}
# }

cd "$(dirname "$0")" || exit 1
source ./.env

# Windows パスをシェル互換パスに変換する関数
# WSL: C:\Users\... → /mnt/c/Users/...
# Git Bash/MSYS2: C:\Users\... → /c/Users/...
# Linux/Unix: そのまま
convert_path() {
  local path="$1"

  # チルダを HOME に展開
  if [[ "$path" == "~"* ]]; then
    path="${HOME}${path:1}"
  fi

  # Windows パス形式かどうかをチェック (例: C:\ or C:/)
  # 正規表現でバックスラッシュを正しくマッチさせるため、^[A-Za-z]: のみでチェック
  if [[ "$path" =~ ^[A-Za-z]: ]]; then
    local third_char="${path:2:1}"
    # 3 文字目がスラッシュまたはバックスラッシュの場合のみ変換
    if [[ "$third_char" == "/" ]] || [[ "$third_char" == '\' ]]; then
      local drive_letter="${path:0:1}"
      local rest="${path:2}"
      # バックスラッシュをスラッシュに変換 (tr を使用)
      rest=$(echo "$rest" | tr '\\' '/')
      # ドライブレターを小文字に変換
      drive_letter=$(echo "$drive_letter" | tr '[:upper:]' '[:lower:]')

      # 環境を検出してパスを変換
      if [[ -f /proc/version ]] && grep -qiE '(microsoft|wsl)' /proc/version 2>/dev/null; then
        # WSL 環境
        path="/mnt/${drive_letter}${rest}"
      elif [[ -n "$MSYSTEM" ]] || [[ "$(uname -s)" == MINGW* ]] || [[ "$(uname -s)" == MSYS* ]]; then
        # Git Bash/MSYS2 環境
        path="/${drive_letter}${rest}"
      fi
    fi
  fi

  echo "$path"
}

# JSON 入力を読み取り
INPUT_JSON=$(cat)

# jq で必要な情報を抽出
SESSION_ID=$(echo "$INPUT_JSON" | jq -r '.session_id // empty')
TRANSCRIPT_PATH_RAW=$(echo "$INPUT_JSON" | jq -r '.transcript_path // empty')
CWD_PATH=$(echo "$INPUT_JSON" | jq -r '.cwd // empty')
TOOL_NAME=$(echo "$INPUT_JSON" | jq -r '.tool_name // empty')
TOOL_INPUT=$(echo "$INPUT_JSON" | jq -r '.tool_input // empty')

# AskUserQuestion 以外は無視
if [[ "$TOOL_NAME" != "AskUserQuestion" ]]; then
  exit 0
fi

# パスを変換
if [[ -n "$TRANSCRIPT_PATH_RAW" ]]; then
  SESSION_PATH=$(convert_path "$TRANSCRIPT_PATH_RAW")
else
  # フォールバック: 従来の方式
  SESSION_PATH="${HOME}/.claude/projects/*/${SESSION_ID}.jsonl"
fi

# transcript_path で指定されたファイルが存在しない場合は通知を送信しない
# ワイルドカードが含まれる場合は展開して確認
if [[ "$SESSION_PATH" == *"*"* ]]; then
  # ワイルドカードを展開
  SESSION_PATH_EXPANDED=($(ls $SESSION_PATH 2>/dev/null || true))
  if [[ ${#SESSION_PATH_EXPANDED[@]} -eq 0 ]]; then
    echo "Session file not found: $SESSION_PATH" >&2
    exit 0
  fi
  SESSION_PATH="${SESSION_PATH_EXPANDED[0]}"
elif [[ ! -f "$SESSION_PATH" ]]; then
  echo "Session file not found: $SESSION_PATH" >&2
  exit 0
fi

webhook_url="${DISCORD_CLAUDE_WEBHOOK}"

if [[ -z "${webhook_url}" ]]; then
  if [[ -n "${CLAUDE_MENTION_USER_ID}" ]]; then
    echo "DISCORD_CLAUDE_WEBHOOK is not set." >&2
    echo "Notification will not be sent." >&2
  fi
  exit 0
fi

if [[ -z "${SESSION_ID}" ]]; then
  if [[ -n "${CLAUDE_MENTION_USER_ID}" ]]; then
    echo "SESSION_ID is not set." >&2
    echo "Notification will not be sent." >&2
  fi
  exit 0
fi

# 質問内容を取得（最初の質問のみ）
QUESTION_TEXT=$(echo "$TOOL_INPUT" | jq -r '.questions[0].question // "質問内容を取得できませんでした"')

# メンション用ユーザー ID を取得（設定されていない場合は空文字列）
MENTION_USER_ID="${DISCORD_CLAUDE_MENTION_USER_ID:-}"
MENTION=""
if [[ -n "$MENTION_USER_ID" ]]; then
  MENTION="<@${MENTION_USER_ID}> "
fi

# 通知メッセージを構築
MESSAGE="${MENTION}**質問が表示されています** 🤔

**質問内容:**
${QUESTION_TEXT}

**Session ID:** \`${SESSION_ID}\`
**CWD:** \`${CWD_PATH}\`"

# Discord Webhook 用の JSON ペイロードを構築
PAYLOAD=$(
  jq -n \
    --arg content "$MESSAGE" \
    '{content: $content}'
)

if [[ -n "${webhook_url}" ]]; then
  SCRIPT_DIR="$(dirname "$0")"

  # バックグラウンドで通知処理を実行
  printf '%s\n' "${PAYLOAD}" | "$SCRIPT_DIR/send-discord-notification.sh" >/dev/null 2>&1 &
fi

exit 0
