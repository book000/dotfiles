#!/usr/bin/env bash

# 現在の PR の URL を ~/.claude/data/session-state.json に書き込み、
# transcript を解析せずに hook から参照できるようにする。
#
# Usage: write-session-state.sh [owner/repo]
#   owner/repo  PR が存在するリポジトリ。`gh pr view --repo` に渡す。
#               省略 (または空文字) の場合は gh の解決に任せる。
# 成功時は書き込んだ PR URL を標準出力に出す。URL が空、または書き込みに失敗した場合は
# 非 0 で終了する。URL が空の場合と gh の失敗時は state ファイルに触れない。jq の書き込み失敗時は
# リダイレクトで state ファイルが空に切り詰められている可能性がある。

set -uo pipefail

REPO="${1:-}"

if ! mkdir -p ~/.claude/data || ! chmod 700 ~/.claude/data; then
  echo "ERROR: failed to prepare ~/.claude/data" >&2
  exit 1
fi

if ! PR_URL=$(gh pr view ${REPO:+--repo "$REPO"} --json url -q .url); then
  echo "ERROR: gh pr view failed, not writing session-state.json" >&2
  exit 1
fi
if [ -z "$PR_URL" ]; then
  echo "ERROR: gh pr view returned an empty URL, not writing session-state.json" >&2
  exit 1
fi

if ! jq -n --arg pr_url "$PR_URL" --arg session_id "${CLAUDE_CODE_SESSION_ID:-}" --argjson timestamp "$(date +%s)" \
    '{"pr_url": $pr_url, "session_id": $session_id, "timestamp": $timestamp}' \
    > ~/.claude/data/session-state.json; then
  echo "ERROR: failed to write session-state.json" >&2
  exit 1
fi

if ! chmod 600 ~/.claude/data/session-state.json; then
  echo "ERROR: failed to chmod session-state.json" >&2
  exit 1
fi

# 呼び出し元がそのまま使えるよう、書き込んだ PR URL を標準出力にも出す。
echo "$PR_URL"
