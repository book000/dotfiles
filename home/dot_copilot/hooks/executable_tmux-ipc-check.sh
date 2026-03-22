#!/bin/bash
# tmux IPC 受信フック (GitHub Copilot CLI userPromptSubmitted)
#
# ユーザープロンプト送信時に inbox をスキャンし、受信メッセージを
# stderr に出力する。Copilot CLI はフックの stderr をモデルへのコンテキストとして
# 渡すため、IPC メッセージが自動的にモデルに伝わる。
# あわせてセッション登録を更新することで、レジストリの alive 状態を維持する。
#
# フック入力 (stdin):
#   {"timestamp": ..., "cwd": "...", "prompt": "..."}
#
# フック出力:
#   stdout: 無視される（Copilot CLI の仕様）
#   stderr: モデルへのコンテキストとして渡される

# stdin から入力 JSON を読み取る（早期 exit の前に必ず消費する）
INPUT_JSON=$(cat)

IPC_DIR="/tmp/tmux-ipc"

# tmux セッション外の場合はスキップ
if [[ -z "${TMUX:-}" ]]; then
  exit 0
fi

# セッション ID を取得
# TMUX_IPC_SESSION_ID が設定されている場合はその値を使用する（テスト・デバッグ用）
if [[ -n "${TMUX_IPC_SESSION_ID:-}" ]]; then
  SESSION_ID="$TMUX_IPC_SESSION_ID"
else
  TMUX_SESSION=$(tmux display-message -p '#S' 2>/dev/null || echo "")
  TMUX_PANE=$(tmux display-message -p '#{pane_id}' 2>/dev/null || echo "")

  if [[ -z "$TMUX_SESSION" || -z "$TMUX_PANE" ]]; then
    exit 0
  fi

  SESSION_ID="${TMUX_SESSION}.${TMUX_PANE}"
fi
INBOX_DIR="$IPC_DIR/$SESSION_ID/inbox"
PROCESSED_DIR="$IPC_DIR/$SESSION_ID/processed"
REGISTRY="$IPC_DIR/registry.json"

# セッションが未登録の場合は register.sh で登録、登録済みの場合は updated 時刻を更新
CURRENT_TIME=$(date +%s)
if [[ ! -d "$IPC_DIR/$SESSION_ID" ]]; then
  # inbox ディレクトリが存在しない場合は初回登録
  REGISTER_SCRIPT="$HOME/bin/tmux-ipc-register.sh"
  if [[ -x "$REGISTER_SCRIPT" ]]; then
    "$REGISTER_SCRIPT" "copilot" >/dev/null 2>&1 || true
  fi
elif [[ -f "$REGISTRY" ]]; then
  # 登録済みの場合は updated タイムスタンプのみ更新
  (
    flock -w 2 200 2>/dev/null || exit 0  # ロック取得失敗時は更新をスキップ
    jq --arg id "$SESSION_ID" --argjson now "$CURRENT_TIME" \
      '(.sessions[] | select(.id == $id) | .updated) = $now' \
      "$REGISTRY" > "${REGISTRY}.tmp" 2>/dev/null \
      && mv "${REGISTRY}.tmp" "$REGISTRY" 2>/dev/null || true
  ) 200>"${REGISTRY}.lock" 2>/dev/null || true
fi

# inbox が存在しない場合はスキップ
if [[ ! -d "$INBOX_DIR" ]]; then
  exit 0
fi

mkdir -p "$PROCESSED_DIR"

MSG_COUNT=0
IPC_SECTION=""

# inbox 内のメッセージを処理
shopt -s nullglob
for msg_file in "$INBOX_DIR"/*.json; do
  [[ -f "$msg_file" ]] || continue

  MSG_JSON=$(cat "$msg_file" 2>/dev/null) || continue

  MSG_ID=$(echo "$MSG_JSON"        | jq -r '.id        // "unknown"')
  MSG_FROM=$(echo "$MSG_JSON"      | jq -r '.from     // "unknown"')
  MSG_TIMESTAMP=$(echo "$MSG_JSON" | jq -r '.timestamp // 0')
  MSG_TTL=$(echo "$MSG_JSON"       | jq -r '.ttl       // 300')
  MSG_BODY=$(echo "$MSG_JSON"      | jq -r '.body     // ""')

  # TTL チェック
  EXPIRY=$((MSG_TIMESTAMP + MSG_TTL))
  if [[ "$CURRENT_TIME" -gt "$EXPIRY" ]]; then
    # TTL 切れ: processed へ移動
    mv "$msg_file" "$PROCESSED_DIR/" 2>/dev/null || rm -f "$msg_file"
    continue
  fi

  # 有効なメッセージを蓄積
  MSG_COUNT=$((MSG_COUNT + 1))
  IPC_SECTION="${IPC_SECTION}
[IPC メッセージ ${MSG_COUNT}] from: ${MSG_FROM} (id: ${MSG_ID})
${MSG_BODY}"

  # processed へ移動
  mv "$msg_file" "$PROCESSED_DIR/" 2>/dev/null || rm -f "$msg_file"
done
shopt -u nullglob

if [[ "$MSG_COUNT" -gt 0 ]]; then
  # stderr にメッセージを書き込む（Copilot CLI はフックの stderr をモデルへのコンテキストとして渡す）
  cat >&2 <<EOF
---
**[tmux IPC] ${MSG_COUNT} 件のメッセージを受信しました:**
${IPC_SECTION}
---
上記は他のエージェントから受信した IPC メッセージです。必要に応じて内容を確認・対応してください。
EOF
fi
