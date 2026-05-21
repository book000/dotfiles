#!/bin/bash
# chezmoi の自動更新スクリプト
# 24 時間以内に実行済みの場合はスキップする

CACHE_DIR="$HOME/.cache/chezmoi-update"
TIMESTAMP_FILE="$CACHE_DIR/last-update"

mkdir -p "$CACHE_DIR"

if [[ -f "$TIMESTAMP_FILE" ]]; then
  last_update=$(cat "$TIMESTAMP_FILE" 2>/dev/null || echo "")
  # 非数値・空の場合は 0 扱いにして算術展開エラーを防ぐ
  [[ "$last_update" =~ ^[0-9]+$ ]] || last_update=0
  elapsed=$(( $(date +%s) - last_update ))
  if [[ $elapsed -lt 86400 ]]; then
    exit 0
  fi
fi

cd "$HOME" || exit
# curl の失敗を検知するため先にインストーラを取得し、成功した場合のみ実行する
if installer=$(curl -fsSL get.chezmoi.io); then
  if sh -c "$installer" -- update; then
    date +%s > "$TIMESTAMP_FILE"
  fi
fi
