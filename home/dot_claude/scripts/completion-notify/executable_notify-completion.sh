#!/bin/bash

# Claude Code Stop hook として動作するスクリプト
# Stop hookは以下の形式のJSONを標準入力から受け取る:
# {
#   "session_id": "string",
#   "transcript_path": "~/.claude/projects/.../session.jsonl",
#   "permission_mode": "string",
#   "hook_event_name": "Stop",
#   "stop_hook_active": boolean
# }

cd "$(dirname "$0")" || exit 1
source ./.env

# Windowsパスをシェル互換パスに変換する関数
# WSL: C:\Users\... → /mnt/c/Users/...
# Git Bash/MSYS2: C:\Users\... → /c/Users/...
# Linux/Unix: そのまま
convert_path() {
  local path="$1"

  # チルダをHOMEに展開
  if [[ "$path" == "~"* ]]; then
    path="${HOME}${path:1}"
  fi

  # Windowsパス形式かどうかをチェック (例: C:\ or C:/)
  # 正規表現でバックスラッシュを正しくマッチさせるため、^[A-Za-z]: のみでチェック
  if [[ "$path" =~ ^[A-Za-z]: ]]; then
    local third_char="${path:2:1}"
    # 3文字目がスラッシュまたはバックスラッシュの場合のみ変換
    if [[ "$third_char" == "/" ]] || [[ "$third_char" == '\' ]]; then
      local drive_letter="${path:0:1}"
      local rest="${path:2}"
      # バックスラッシュをスラッシュに変換 (tr を使用)
      rest=$(echo "$rest" | tr '\\' '/')
      # ドライブレターを小文字に変換
      drive_letter=$(echo "$drive_letter" | tr '[:upper:]' '[:lower:]')

      # 環境を検出してパスを変換
      if [[ -f /proc/version ]] && grep -qiE '(microsoft|wsl)' /proc/version 2>/dev/null; then
        # WSL環境
        path="/mnt/${drive_letter}${rest}"
      elif [[ -n "$MSYSTEM" ]] || [[ "$(uname -s)" == MINGW* ]] || [[ "$(uname -s)" == MSYS* ]]; then
        # Git Bash/MSYS2環境
        path="/${drive_letter}${rest}"
      fi
    fi
  fi

  echo "$path"
}

# Agent Teams のリーダーエージェントかどうかを判定する関数
# 入力: session_id
# 出力: "true" (リーダー), "false" (メンバー), "unknown" (判定不可)
is_team_lead() {
  local session_id="$1"

  # session_id が空の場合は判定不可
  if [[ -z "$session_id" ]]; then
    echo "unknown"
    return
  fi

  # ~/.claude/teams/ ディレクトリが存在しない場合は判定不可
  if [[ ! -d "${HOME}/.claude/teams" ]]; then
    echo "unknown"
    return
  fi

  # ~/.claude/teams/*/config.json を検索
  for config_file in "${HOME}/.claude/teams"/*/config.json; do
    # ワイルドカードが展開されなかった場合（マッチなし）
    if [[ ! -f "$config_file" ]]; then
      continue
    fi

    # config.json から members 配列を取得し、session_id と agentId を照合
    # 複数のマッチがある場合は最初のマッチのみを使用
    local agent_type
    agent_type=$(jq -r --arg sid "$session_id" \
      '[.members[]? | select(.agentId == $sid) | .agentType // empty] | first' \
      "$config_file" 2>/dev/null)

    # agentType が取得できた場合
    if [[ -n "$agent_type" ]]; then
      # agentType が "lead" または "team-lead" の場合はリーダー
      if [[ "$agent_type" == "lead" ]] || [[ "$agent_type" == "team-lead" ]]; then
        echo "true"
        return
      # agentType が "member" または "teammate" の場合はメンバー
      elif [[ "$agent_type" == "member" ]] || [[ "$agent_type" == "teammate" ]]; then
        echo "false"
        return
      fi
    fi
  done

  # 判定不可
  echo "unknown"
}

# JSON入力を読み取り
INPUT_JSON=$(cat)

# jqで必要な情報を抽出
SESSION_ID=$(echo "$INPUT_JSON" | jq -r '.session_id // empty')
TRANSCRIPT_PATH_RAW=$(echo "$INPUT_JSON" | jq -r '.transcript_path // empty')
CWD_PATH=$(echo "$INPUT_JSON" | jq -r '.cwd // empty')

# リーダーエージェントかどうかを判定（早期チェック）
AGENT_ROLE=$(is_team_lead "$SESSION_ID")

# Discord 通知の条件分岐（早期 exit でパフォーマンス改善）
if [[ "$AGENT_ROLE" == "false" ]]; then
  echo "⏭️ Teammate agent detected. Skipping Discord notification." >&2
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

# フィールド: 入力JSON
FIELDS=$(echo "$FIELDS" | jq --arg name "📝 入力JSON" --arg value "$INPUT_JSON" --arg inline "false" \
  '. + [{"name": $name, "value": $value, "inline": $inline}]')

# フィールド: 区切り (nameは zero-width space)
FIELDS=$(echo "$FIELDS" | jq --arg name "​" --arg value "------------------------------" --arg inline "false" \
  '. + [{"name": $name, "value": $value, "inline": $inline}]')

# jq -r 'select((.type == "assistant" or .type == "user") and .message.type == "message") | .type as $t | .message.content[]? | select(.type=="text") | [$t, .text] | @tsv' 9c213bb5-37f7-40b6-a588-5afe17407064.jsonl
# 複数フィールド: 最新5件のメッセージを取得
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

content="Claude Code Finished (${MACHINE_NAME})"
if [[ -n "${MENTION_USER_ID}" ]]; then
  content="<@${MENTION_USER_ID}> ${content}"
fi

# embed 形式の JSON ペイロードを作成（jq を使用して適切にエスケープ）
PAYLOAD=$(jq -n \
  --arg content "$content" \
  --arg timestamp "$TIMESTAMP" \
  --argjson fields "$FIELDS" \
  '{
    content: $content,
    embeds: [{
      title: "Claude Code セッション完了",
      color: 5763719,
      timestamp: $timestamp,
      fields: $fields
    }]
  }')

# Discord 通知を送信（リーダーエージェントまたは判定不可の場合）
if [[ "$AGENT_ROLE" == "true" ]]; then
  echo "✅ Lead agent detected. Sending Discord notification." >&2
else
  echo "⚠️ Agent role undetermined. Sending Discord notification as fallback." >&2
fi

webhook_url="${DISCORD_WEBHOOK_URL}"
if [[ -n "${webhook_url}" ]]; then
  # バックグラウンドで通知処理を実行
  SCRIPT_DIR="$(dirname "$0")"
  printf '%s\n' "${PAYLOAD}" | "$SCRIPT_DIR/send-discord-notification.sh" >/dev/null 2>&1 &
fi
