#!/bin/bash
# chezmoi の自動更新スクリプト
# 24 時間以内に実行済みの場合はスキップする

CACHE_DIR="$HOME/.cache/chezmoi-update"
TIMESTAMP_FILE="$CACHE_DIR/last-update"

mkdir -p "$CACHE_DIR"

if [[ -f "$TIMESTAMP_FILE" ]]; then
  last_update=$(cat "$TIMESTAMP_FILE" 2>/dev/null || echo 0)
  elapsed=$(( $(date +%s) - last_update ))
  if [[ $elapsed -lt 86400 ]]; then
    exit 0
  fi
fi

cd "$HOME" || exit
if sh -c "$(curl -fsSL get.chezmoi.io)" -- update; then
  date +%s > "$TIMESTAMP_FILE"
fi
