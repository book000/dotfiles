#!/bin/bash

# Claude Code Notification hook として動作するスクリプト
# Notification hook は以下の形式の JSON を標準入力から受け取る:
# {
#   "session_id": "string",
#   "transcript_path": "~/.claude/projects/.../session.jsonl",
#   "cwd": "string",
#   "permission_mode": "string",
#   "hook_event_name": "Notification",
#   "message": "string",
#   "title": "string",
#   "notification_type": "string"
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
MESSAGE=$(echo "$INPUT_JSON" | jq -r '.message // empty')
TITLE=$(echo "$INPUT_JSON" | jq -r '.title // empty')
NOTIFICATION_TYPE=$(echo "$INPUT_JSON" | jq -r '.notification_type // empty')

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

# 通知タイプに応じた絵文字とタイトルを設定
case "$NOTIFICATION_TYPE" in
  permission_prompt)
    EMOJI="⚠️"
    EMBED_TITLE="Claude Code 権限プロンプト"
    COLOR=16776960  # 黄色
    ;;
  idle_prompt)
    EMOJI="💤"
    EMBED_TITLE="Claude Code アイドル通知"
    COLOR=8421504  # グレー
    ;;
  auth_success)
    EMOJI="✅"
    EMBED_TITLE="Claude Code 認証成功"
    COLOR=5763719  # 緑色
    ;;
  elicitation_dialog)
    EMOJI="💬"
    EMBED_TITLE="Claude Code ダイアログ"
    COLOR=3447003  # 青色
    ;;
  *)
    EMOJI="🔔"
    EMBED_TITLE="Claude Code 通知"
    COLOR=3447003  # 青色
    ;;
esac

# フィールドの構築
FIELDS="[]"

# フィールド: 実行ディレクトリ
FIELDS=$(echo "$FIELDS" | jq --arg name "📁 実行ディレクトリ" --arg value "$CWD_PATH" --arg inline "true" \
  '. + [{"name": $name, "value": $value, "inline": $inline}]')

# フィールド: セッション ID
FIELDS=$(echo "$FIELDS" | jq --arg name "🆔 セッション ID" --arg value "$SESSION_ID" --arg inline "true" \
  '. + [{"name": $name, "value": $value, "inline": $inline}]')

# フィールド: 通知タイプ
FIELDS=$(echo "$FIELDS" | jq --arg name "📋 通知タイプ" --arg value "$NOTIFICATION_TYPE" --arg inline "true" \
  '. + [{"name": $name, "value": $value, "inline": $inline}]')

# フィールド: タイトル (存在する場合)
if [[ -n "$TITLE" ]]; then
  FIELDS=$(echo "$FIELDS" | jq --arg name "📌 タイトル" --arg value "$TITLE" --arg inline "false" \
    '. + [{"name": $name, "value": $value, "inline": $inline}]')
fi

# フィールド: メッセージ
FIELDS=$(echo "$FIELDS" | jq --arg name "💬 メッセージ" --arg value "$MESSAGE" --arg inline "false" \
  '. + [{"name": $name, "value": $value, "inline": $inline}]')

# フィールド: 入力 JSON
FIELDS=$(echo "$FIELDS" | jq --arg name "📝 入力 JSON" --arg value "$INPUT_JSON" --arg inline "false" \
  '. + [{"name": $name, "value": $value, "inline": $inline}]')

# フィールド: 区切り (name は zero-width space)
FIELDS=$(echo "$FIELDS" | jq --arg name "​" --arg value "------------------------------" --arg inline "false" \
  '. + [{"name": $name, "value": $value, "inline": $inline}]')

# 複数フィールド: 最新 5 件のメッセージを取得
LAST_MESSAGES=$(jq -r '
  select(
    (.type == "user" and .message.role == "user" and (.message.content | type) == "string") or
    (.type == "assistant" and .message.type == "message")
  )
  | [.type,
     (if .type == "user" then .message.content
      else ([.message.content[]? | select(.type=="text") | .text] | join(" ")) end)
    ]
  | select(.[1] != "")
  | @tsv
' $SESSION_PATH | tail -n 5)
if [[ -n "$LAST_MESSAGES" ]]; then
  IFS=$'\n' read -r -d '' -a messages_array <<< "$LAST_MESSAGES"
  for message in "${messages_array[@]}"; do
    IFS=$'\t' read -r type text <<< "$message"
    # "\\n" を本当の改行 "\n" に変換
    text=$(echo -e "${text//\\n/$'\n'}")
    if [[ "$type" == "user" ]]; then
      emoji="👤"
    else
      emoji="🤖"
    fi
    FIELDS=$(echo "$FIELDS" | jq --arg name "${emoji} 会話: $type" --arg value "$text" --arg inline "false" \
      '. + [{"name": $name, "value": $value, "inline": $inline}]')
  done
fi

content="${EMOJI} Claude Code Notification (${MACHINE_NAME})"
if [[ -n "${MENTION_USER_ID}" ]]; then
  content="<@${MENTION_USER_ID}> ${content}"
fi

# embed 形式の JSON ペイロードを作成（jq を使用して適切にエスケープ）
PAYLOAD=$(jq -n \
  --arg content "$content" \
  --arg title "$EMBED_TITLE" \
  --arg description "$MESSAGE" \
  --arg timestamp "$TIMESTAMP" \
  --argjson color "$COLOR" \
  --argjson fields "$FIELDS" \
  '{
    content: $content,
    embeds: [{
      title: $title,
      description: $description,
      color: $color,
      timestamp: $timestamp,
      fields: $fields
    }]
  }')

webhook_url="${DISCORD_WEBHOOK_URL}"
if [[ -n "${webhook_url}" ]]; then
  # バックグラウンドで通知処理を実行
  SCRIPT_DIR="$(dirname "$0")"
  printf '%s\n' "${PAYLOAD}" | "$SCRIPT_DIR/send-discord-notification.sh" >/dev/null 2>&1 &
fi
