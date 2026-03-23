#!/bin/bash
# tmux IPC クリーンアップスクリプト
#
# 以下を削除・整理する:
#   - inbox 内の TTL 超過メッセージ
#   - processed/ 内の古いメッセージ (デフォルト 24 時間経過後)
#   - registry から非アクティブセッション (デフォルト 1 時間以上更新なし)
#
# Usage: tmux-ipc-cleanup.sh [--session-timeout SECONDS] [--processed-retention SECONDS]
#   --session-timeout    : セッションタイムアウト秒。デフォルト 3600
#   --processed-retention: processed 保持秒。デフォルト 86400

set -euo pipefail

IPC_DIR="/tmp/tmux-ipc"
REGISTRY="$IPC_DIR/registry.json"

# デフォルト値
SESSION_TIMEOUT=3600    # 1 時間
PROCESSED_RETENTION=86400  # 24 時間

# 引数を解析
while [[ $# -gt 0 ]]; do
  case "$1" in
    --session-timeout)
      SESSION_TIMEOUT="$2"
      shift 2
      ;;
    --processed-retention)
      PROCESSED_RETENTION="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

if [[ ! -d "$IPC_DIR" ]]; then
  echo "[tmux-ipc-cleanup] No IPC directory found, nothing to clean"
  exit 0
fi

CURRENT_TIME=$(date +%s)
INBOX_EXPIRED=0
PROCESSED_REMOVED=0
SESSIONS_REMOVED=0

# 1. inbox 内の TTL 超過メッセージを削除
shopt -s nullglob
for inbox_dir in "$IPC_DIR"/*/inbox; do
  [[ -d "$inbox_dir" ]] || continue
  for msg_file in "$inbox_dir"/*.json; do
    [[ -f "$msg_file" ]] || continue
    MSG_JSON=$(cat "$msg_file" 2>/dev/null) || continue
    MSG_TIMESTAMP=$(echo "$MSG_JSON" | jq -r '.timestamp // 0')
    MSG_TTL=$(echo "$MSG_JSON" | jq -r '.ttl // 300')
    EXPIRY=$((MSG_TIMESTAMP + MSG_TTL))
    if [[ "$CURRENT_TIME" -gt "$EXPIRY" ]]; then
      rm -f "$msg_file"
      INBOX_EXPIRED=$((INBOX_EXPIRED + 1))
    fi
  done
done

# 2. processed/ 内の古いメッセージを削除
for processed_dir in "$IPC_DIR"/*/processed; do
  [[ -d "$processed_dir" ]] || continue
  for msg_file in "$processed_dir"/*.json; do
    [[ -f "$msg_file" ]] || continue
    MSG_JSON=$(cat "$msg_file" 2>/dev/null) || continue
    MSG_TIMESTAMP=$(echo "$MSG_JSON" | jq -r '.timestamp // 0')
    RETENTION_EXPIRY=$((MSG_TIMESTAMP + PROCESSED_RETENTION))
    if [[ "$CURRENT_TIME" -gt "$RETENTION_EXPIRY" ]]; then
      rm -f "$msg_file"
      PROCESSED_REMOVED=$((PROCESSED_REMOVED + 1))
    fi
  done
done
shopt -u nullglob

# 3. registry から非アクティブセッションを削除
# サブシェル内の変数はメインシェルに伝播しないため、一時ファイルで結果を受け渡す
SESSIONS_COUNT_FILE=$(mktemp)
trap 'rm -f "$SESSIONS_COUNT_FILE"' EXIT

if [[ -f "$REGISTRY" ]]; then
  (
    flock -w 5 200 || { echo "Error: Failed to acquire lock on registry" >&2; exit 1; }

    BEFORE_COUNT=$(jq '.sessions | length' "$REGISTRY" 2>/dev/null || echo 0)

    CUTOFF=$((CURRENT_TIME - SESSION_TIMEOUT))
    jq --argjson cutoff "$CUTOFF" \
      '.sessions = [.sessions[] | select(.updated > $cutoff)]' \
      "$REGISTRY" > "${REGISTRY}.tmp" && mv "${REGISTRY}.tmp" "$REGISTRY"

    AFTER_COUNT=$(jq '.sessions | length' "$REGISTRY" 2>/dev/null || echo 0)
    # サブシェルから結果を一時ファイルに書き出す
    echo $((BEFORE_COUNT - AFTER_COUNT)) > "$SESSIONS_COUNT_FILE"

  ) 200>"${REGISTRY}.lock"
fi

SESSIONS_REMOVED=$(cat "$SESSIONS_COUNT_FILE" 2>/dev/null || echo 0)

echo "[tmux-ipc-cleanup] Done: inbox_expired=${INBOX_EXPIRED}, processed_removed=${PROCESSED_REMOVED}, sessions_removed=${SESSIONS_REMOVED}"
