#!/usr/bin/env bash
set -euo pipefail

# jq がインストールされているか確認
if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required for gemini notify hook." >&2
  exit 1
fi

# Windows パスをシェル互換パスに変換する
# WSL: C:\Users\... -> /mnt/c/Users/...
# Git Bash/MSYS2: C:\Users\... -> /c/Users/...
# Linux/Unix: そのまま
convert_path() {
  local path="$1"

  # チルダを展開
  if [[ "$path" == "~"* ]]; then
    path="${HOME}${path:1}"
  fi

  # Windowsパス形式 (例: C:\ or C:/) をチェック
  if [[ "$path" =~ ^[A-Za-z]:[/\\] ]]; then
    local drive_letter
    drive_letter=$(echo "${path:0:1}" | tr '[:upper:]' '[:lower:]')
    # shellcheck disable=SC1003
    local rest
    rest=$(echo "${path:2}" | tr '\\' '/')

    # 環境を検出してパスを変換
    if [[ -f /proc/version ]] && grep -qiE '(microsoft|wsl)' /proc/version 2>/dev/null; then
      path="/mnt/${drive_letter}${rest}"
    elif [[ -n "${MSYSTEM:-}" ]] || [[ "$(uname -s)" == MINGW* ]] || [[ "$(uname -s)" == MSYS* ]]; then
      path="/${drive_letter}${rest}"
    fi
  fi

  echo "$path"
}

# Discord field の文字数上限を超えないように切り詰める
truncate_field_value() {
  local value="$1"
  local max_length="${2:-1000}"

  if (( ${#value} > max_length )); then
    printf '%s' "${value:0:max_length-3}..."
  else
    printf '%s' "$value"
  fi
}

# 標準入力からJSONを読み込み
INPUT_JSON=$(cat)

# 必要な情報を抽出 (jq のエラーを許容し、フォールバックを用意)
SESSION_ID=$(echo "$INPUT_JSON" | jq -r '.session_id // empty' 2>/dev/null || true)
CWD_PATH=$(echo "$INPUT_JSON" | jq -r '.cwd // empty' 2>/dev/null || true)
TRANSCRIPT_PATH_RAW=$(echo "$INPUT_JSON" | jq -r '.transcript_path // empty' 2>/dev/null || true)

# 環境変数からのフォールバック
if [[ -z "$SESSION_ID" ]]; then
  SESSION_ID=${GEMINI_SESSION_ID:-""}
fi
if [[ -z "$CWD_PATH" ]]; then
  CWD_PATH=${GEMINI_CWD:-""}
fi

# パスを変換
if [[ -n "$TRANSCRIPT_PATH_RAW" ]]; then
  TRANSCRIPT_PATH=$(convert_path "$TRANSCRIPT_PATH_RAW")
else
  TRANSCRIPT_PATH=""
fi

# 通知設定を読み込み
config="${HOME}/.config/notify/gemini.env"
if [[ -f "$config" ]]; then
  # shellcheck source=/dev/null
  source "$config"
fi

# Webhook URLがなければ即時終了
if [[ -z "${DISCORD_WEBHOOK_URL:-}" ]]; then
  printf '{}\n'
  exit 0
fi

# Discordペイロードの構築
timestamp=$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")
hostname_val=$(hostname)

fields="[]"
fields=$(echo "$fields" | jq --arg name "📁 実行ディレクトリ" --arg value "$CWD_PATH" \
  '. + [{"name": $name, "value": ($value|if .=="" then "(unknown)" else . end), "inline": true}]')
fields=$(echo "$fields" | jq --arg name "🆔 セッション ID" --arg value "$SESSION_ID" \
  '. + [{"name": $name, "value": ($value|if .=="" then "(unknown)" else . end), "inline": true}]')

input_json_preview=$(truncate_field_value "$INPUT_JSON" 1000)
fields=$(echo "$fields" | jq --arg name "📝 入力 JSON" --arg value "$input_json_preview" \
  '. + [{"name": $name, "value": ($value|if .=="" then "(empty)" else . end), "inline": false}]')
fields=$(echo "$fields" | jq --arg name "​" --arg value "------------------------------" \
  '. + [{"name": $name, "value": $value, "inline": false}]')

# トランスクリプトから最新の会話を抽出
if [[ -n "$TRANSCRIPT_PATH" ]] && [[ -f "$TRANSCRIPT_PATH" ]]; then
  # jq の実行結果を安全に評価
  if last_messages=$(jq -r '
    .messages[]?
    | select(.type == "user" or .type == "gemini")
    | [
        .type,
        (
          if (.content | type) == "string" then .content
          elif (.content | type) == "array" then
            ([
              .content[]?
              | if type == "string" then .
                elif (type == "object" and .text? != null) then .text
                elif (type == "object" and .functionCall? != null) then
                  ("[functionCall:" + (.functionCall.name // "unknown") + "]")
                elif (type == "object" and .functionResponse? != null) then
                  ("[functionResponse:" + (.functionResponse.name // "unknown") + "]")
                else empty
                end
            ] | join(" "))
          elif (.content | type) == "object" then ((.content.text // empty) | tostring)
          else ""
          end
        )
      ]
    | select(.[1] != "")
    | @tsv
  ' "$TRANSCRIPT_PATH" 2>/dev/null | tail -n 5); then

    if [[ -n "$last_messages" ]]; then
      while IFS=$'\t' read -r message_type message_text; do
        [[ -z "$message_type" ]] && continue

        message_text=$(echo -e "${message_text//\\n/$'\n'}")
        message_text=$(truncate_field_value "$message_text" 1000)

        if [[ "$message_type" == "user" ]]; then
          message_emoji="👤"
        else
          message_emoji="🤖"
        fi

        fields=$(echo "$fields" | jq \
          --arg name "${message_emoji} 会話: ${message_type}" \
          --arg value "$message_text" \
          '. + [{"name": $name, "value": ($value|if .=="" then "(empty)" else . end), "inline": false}]')
      done <<< "$last_messages"
    fi
  else
    echo "Failed to parse transcript JSON: $TRANSCRIPT_PATH" >&2
  fi
elif [[ -n "$TRANSCRIPT_PATH" ]]; then
  echo "Transcript file not found: $TRANSCRIPT_PATH" >&2
fi

# メンションを追加
mention=""
if [[ -n "${DISCORD_MENTION_USER_ID:-}" ]]; then
  mention="<@${DISCORD_MENTION_USER_ID}> "
fi

# 最終的なペイロードを作成
payload=$(jq -n \
  --arg content "${mention}Gemini CLI Finished (${hostname_val})" \
  --arg title "Gemini CLI セッション完了" \
  --arg ts "$timestamp" \
  --argjson fields "$fields" \
  '{
    content: $content,
    embeds: [
      {
        title: $title,
        color: 5763719,
        timestamp: $ts,
        fields: $fields
      }
    ]
  }')

# 通知をバックグラウンドで送信
curl -fsS -H "Content-Type: application/json" -d "$payload" "$DISCORD_WEBHOOK_URL" >/dev/null 2>&1 &

# フックの正常終了をCLIに伝える
printf '{}\n'
