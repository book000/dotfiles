#!/bin/bash
# tmux IPC セッション登録スクリプト
#
# 現在の tmux セッション/ペインを registry.json に登録する。
# 登録により、他のエージェントがこのセッション宛にメッセージを送れるようになる。
#
# Usage: tmux-ipc-register.sh [agent_type]
#   agent_type: claude | gemini | codex | copilot | unknown (省略時は自動検出)

set -euo pipefail

IPC_DIR="/tmp/tmux-ipc"
REGISTRY="$IPC_DIR/registry.json"

# tmux セッション内かどうか確認
if [[ -z "${TMUX:-}" ]]; then
  echo "Error: Not in a tmux session" >&2
  exit 1
fi

# セッション ID を取得
TMUX_SESSION=$(tmux display-message -p '#S' 2>/dev/null || echo "")
TMUX_PANE=$(tmux display-message -p '#{pane_id}' 2>/dev/null || echo "")

if [[ -z "$TMUX_SESSION" || -z "$TMUX_PANE" ]]; then
  echo "Error: Failed to get tmux session/pane info" >&2
  exit 1
fi

SESSION_ID="${TMUX_SESSION}.${TMUX_PANE}"

# エージェント種別を自動検出する関数
detect_agent() {
  local pane_cmd
  pane_cmd=$(tmux display-message -p '#{pane_current_command}' 2>/dev/null || echo "unknown")

  case "$pane_cmd" in
    *claude*)  echo "claude" ;;
    *gemini*)  echo "gemini" ;;
    *codex*)   echo "codex" ;;
    *copilot*) echo "copilot" ;;
    *)         echo "unknown" ;;
  esac
}

AGENT="${1:-$(detect_agent)}"
CURRENT_TIME=$(date +%s)

# ディレクトリを作成
mkdir -p "$IPC_DIR/${SESSION_ID}/inbox"
mkdir -p "$IPC_DIR/${SESSION_ID}/processed"

# registry.json の排他更新 (flock を使用)
(
  flock -w 5 200 || { echo "Error: Failed to acquire lock on registry" >&2; exit 1; }

  NEW_ENTRY=$(jq -n \
    --arg     id      "$SESSION_ID" \
    --arg     agent   "$AGENT" \
    --argjson updated "$CURRENT_TIME" \
    '{"id": $id, "agent": $agent, "updated": $updated}')

  if [[ -f "$REGISTRY" ]]; then
    # 既存エントリを更新（同一 session_id を削除して追加）
    jq --argjson entry "$NEW_ENTRY" \
      '.sessions = ([.sessions[] | select(.id != $entry.id)] + [$entry])' \
      "$REGISTRY" > "${REGISTRY}.tmp" && mv "${REGISTRY}.tmp" "$REGISTRY"
  else
    # 新規作成
    jq -n --argjson entry "$NEW_ENTRY" '{"sessions": [$entry]}' > "$REGISTRY"
  fi

) 200>"${REGISTRY}.lock"

echo "Registered: $SESSION_ID (agent: $AGENT)"
