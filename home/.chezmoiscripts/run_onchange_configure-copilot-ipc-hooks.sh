#!/bin/bash
# GitHub Copilot CLI の config.json に tmux IPC フックを追加する
#
# ~/.copilot/config.json は認証トークンを含むため chezmoi で直接管理しない。
# このスクリプトが hooks セクションのみを非破壊的に追加・更新する。
#
# このスクリプトは以下のファイルが変更された場合に再実行される:
#   - home/dot_copilot/hooks/executable_tmux-ipc-check.sh

# hash: {{ include "dot_copilot/hooks/executable_tmux-ipc-check.sh" | sha256sum }}

set -euo pipefail

CONFIG="$HOME/.copilot/config.json"
HOOK_SCRIPT="$HOME/.copilot/hooks/tmux-ipc-check.sh"

if [[ ! -f "$CONFIG" ]]; then
  echo "[copilot-ipc-hooks] ~/.copilot/config.json が存在しないためスキップします"
  exit 0
fi

if ! command -v jq &>/dev/null; then
  echo "[copilot-ipc-hooks] jq が見つからないためスキップします" >&2
  exit 0
fi

# すでに設定済みかチェック
if jq -e '.hooks.postToolUse // empty' "$CONFIG" > /dev/null 2>&1; then
  echo "[copilot-ipc-hooks] postToolUse フックは既に設定済みです"
  exit 0
fi

# hooks.postToolUse を追加（既存の設定を保持）
UPDATED=$(jq --arg script "$HOOK_SCRIPT" '
  .hooks.postToolUse = [
    {
      "type": "command",
      "bash": $script
    }
  ]
' "$CONFIG") || { echo "[copilot-ipc-hooks] jq によるフック追加に失敗しました" >&2; exit 1; }

echo "$UPDATED" > "$CONFIG"
echo "[copilot-ipc-hooks] postToolUse フックを ~/.copilot/config.json に追加しました"
