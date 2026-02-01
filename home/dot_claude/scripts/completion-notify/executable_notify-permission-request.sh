#!/bin/bash

# Claude Code PermissionRequest hook として動作するスクリプト
# PermissionRequest hook は以下の形式の JSON を標準入力から受け取る:
# {
#   "session_id": "string",
#   "transcript_path": "~/.claude/projects/.../session.jsonl",
#   "cwd": "string",
#   "permission_mode": "string",
#   "hook_event_name": "PermissionRequest",
#   "tool_name": "string",
#   "tool_input": {...},
#   "permission_suggestions": [...]
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
TOOL_INPUT=$(echo "$INPUT_JSON" | jq -c '.tool_input // {}')

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
  # ワイルドカードを展開 (compgen を使用して安全に展開)
  # ※ マッチするファイルがない場合、配列は空になる
  mapfile -t EXPANDED_PATHS < <(compgen -G "$SESSION_PATH")
  if [[ ${#EXPANDED_PATHS[@]} -eq 0 ]]; then
    echo "⚠️ Transcript file not found: $SESSION_PATH" >&2
    echo "Notification will not be sent." >&2
    exit 0
  fi
  SESSION_PATH="${EXPANDED_PATHS[0]}"
else
  # 通常のパスの場合
  if [[ ! -f "$SESSION_PATH" ]]; then
    echo "⚠️ Transcript file not found: $SESSION_PATH" >&2
    echo "Notification will not be sent." >&2
    exit 0
  fi
fi

# 現在時刻の取得
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")

# マシン名の取得
MACHINE_NAME=$(hostname)

# フィールドの構築
FIELDS="[]"

# フィールド: 実行ディレクトリ
FIELDS=$(echo "$FIELDS" | jq --arg name "📁 実行ディレクトリ" --arg value "$CWD_PATH" --arg inline "true" \
  '. + [{"name": $name, "value": $value, "inline": $inline}]')

# フィールド: セッション ID
FIELDS=$(echo "$FIELDS" | jq --arg name "🆔 セッション ID" --arg value "$SESSION_ID" --arg inline "true" \
  '. + [{"name": $name, "value": $value, "inline": $inline}]')

# フィールド: ツール名
FIELDS=$(echo "$FIELDS" | jq --arg name "🔧 ツール名" --arg value "$TOOL_NAME" --arg inline "true" \
  '. + [{"name": $name, "value": $value, "inline": $inline}]')

# フィールド: ツール入力
FIELDS=$(echo "$FIELDS" | jq --arg name "⚙️ ツール入力" --argjson value "$TOOL_INPUT" --arg inline "false" \
  '. + [{"name": $name, "value": ($value | tostring), "inline": $inline}]')

# フィールド: 入力 JSON
FIELDS=$(echo "$FIELDS" | jq --arg name "📝 入力 JSON" --arg value "$INPUT_JSON" --arg inline "false" \
  '. + [{"name": $name, "value": $value, "inline": $inline}]')

content="Claude Code Permission Request (${MACHINE_NAME})"
if [[ -n "${MENTION_USER_ID}" ]]; then
  content="<@${MENTION_USER_ID}> ${content}"
fi

# Discord メッセージの description を構築
description="Claude が **${TOOL_NAME}** ツールの使用許可を求めています。"

# embed 形式の JSON ペイロードを作成（jq を使用して適切にエスケープ）
PAYLOAD=$(jq -n \
  --arg content "$content" \
  --arg description "$description" \
  --arg timestamp "$TIMESTAMP" \
  --argjson fields "$FIELDS" \
  '{
    content: $content,
    embeds: [{
      title: "⚠️ Claude Code 権限リクエスト",
      description: $description,
      color: 16776960,
      timestamp: $timestamp,
      fields: $fields
    }]
  }')

webhook_url="${DISCORD_WEBHOOK_URL}"
if [[ -n "${webhook_url}" ]]; then
  # Discord Webhook に送信
  curl -H "Content-Type: application/json" \
       -X POST \
       -d "${PAYLOAD}" \
       "${webhook_url}"
fi
