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
# shellcheck source=/dev/null
source ./.env
# shellcheck source=./lib.sh
source "$(dirname "$0")/lib.sh"

# データディレクトリの作成
DATA_DIR="$HOME/.claude/scripts/completion-notify/data"
mkdir -p "$DATA_DIR"

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

# データディレクトリの作成
DATA_DIR="$HOME/.claude/scripts/completion-notify/data"
mkdir -p "$DATA_DIR"

# idle_prompt の重複送信防止ロジック
if [[ "$NOTIFICATION_TYPE" == "idle_prompt" ]]; then
  # SESSION_ID が空の場合はスキップ（セッション単位の管理ができない）
  if [[ -z "$SESSION_ID" ]]; then
    echo "⚠️ SESSION_ID is empty, skipping cooldown check" >&2
  else
    # セッション ID ごとに最後の通知タイムスタンプを記録
    LAST_IDLE_NOTIFY_FILE="$DATA_DIR/last-idle-notify-${SESSION_ID}.txt"
    LOCK_DIR="$DATA_DIR/last-idle-notify-${SESSION_ID}.lock"
    COOLDOWN_SECONDS=60  # 60 秒以内の重複通知をスキップ

    # ロック取得を試行（mkdir はアトミック操作）
    if mkdir "$LOCK_DIR" 2>/dev/null; then
      # ロック取得に成功した場合のみ処理を続行
      trap 'rmdir "$LOCK_DIR" 2>/dev/null' EXIT

      # 最後の通知時刻を取得
      if [[ -f "$LAST_IDLE_NOTIFY_FILE" ]]; then
        LAST_NOTIFY_TIME=$(cat "$LAST_IDLE_NOTIFY_FILE")

        # 数値検証（既存コードの send-discord-notification.sh と同じパターン）
        if [[ "$LAST_NOTIFY_TIME" =~ ^[0-9]+$ ]]; then
          CURRENT_TIME=$(date +%s)
          ELAPSED=$((CURRENT_TIME - LAST_NOTIFY_TIME))

          if [[ $ELAPSED -lt $COOLDOWN_SECONDS ]]; then
            echo "⏱️ Skipping idle_prompt notification (cooldown: ${ELAPSED}s < ${COOLDOWN_SECONDS}s)" >&2
            rmdir "$LOCK_DIR" 2>/dev/null
            exit 0
          fi
        else
          echo "⚠️ LAST_NOTIFY_TIME is invalid, skipping cooldown check" >&2
        fi
      fi

      # 現在時刻を記録
      date +%s > "$LAST_IDLE_NOTIFY_FILE"
      rmdir "$LOCK_DIR" 2>/dev/null
    else
      # ロック取得に失敗した場合は別プロセスが処理中なのでスキップ
      echo "⏸️ Another process is checking idle_prompt cooldown, skipping" >&2
      exit 0
    fi
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
' "$SESSION_PATH" | tail -n 5)
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
  SCRIPT_DIR="$(dirname "$0")"

  # idle_prompt の場合は待機時間を調整
  if [[ "$NOTIFICATION_TYPE" == "idle_prompt" ]]; then
    # AskUserQuestion 表示中フラグが存在する場合は通知を送信しない
    if [[ -f "$DATA_DIR/askuserquestion-active-${SESSION_ID}.flag" ]]; then
      # フラグのタイムスタンプを確認（1時間以上古い場合は無視）
      FLAG_TIMESTAMP=$(cat "$DATA_DIR/askuserquestion-active-${SESSION_ID}.flag" 2>/dev/null || echo "0")
      CURRENT_TIME=$(date +%s)
      # タイムスタンプが数値かつ1時間以内（3600秒）の場合のみ通知を抑制
      if [[ "$FLAG_TIMESTAMP" =~ ^[0-9]+$ ]] && (( CURRENT_TIME - FLAG_TIMESTAMP < 3600 )); then
        exit 0
      fi
      # 古いフラグは削除
      rm -f "$DATA_DIR/askuserquestion-active-${SESSION_ID}.flag" 2>/dev/null
    fi

    # idle_prompt は既に 60 秒待機しているため、即座に通知
    # 環境変数で待機時間を 0 秒に設定
    export NOTIFICATION_DELAY=0
  fi

  # バックグラウンドで通知処理を実行（セッション ID を環境変数で渡す）
  export NOTIFICATION_SESSION_ID="$SESSION_ID"
  printf '%s\n' "${PAYLOAD}" | "$SCRIPT_DIR/send-discord-notification.sh" >/dev/null 2>&1 &
fi
