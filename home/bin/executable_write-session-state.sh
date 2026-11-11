#!/usr/bin/env bash

# 現在の PR の URL を ~/.claude/data/session-state-<session_id>.json に書き込み、
# transcript を解析せずに hook から参照できるようにする。セッションごとに別ファイルなので、
# 並行して動く別セッションの state を上書きしない。
#
# Usage: write-session-state.sh [owner/repo]
#   owner/repo  PR が存在するリポジトリ。origin の owner と現在のブランチ名から
#               `<origin の owner>:<branch>` を作り、そのリポジトリの PR を特定する
#               (fork の PR や upstream 追跡のないブランチでも解決できる)。
#               省略 (または空文字) の場合は gh の解決に任せる。
# 成功時は PR URL を標準出力に出す。URL が空、gh の失敗、または書き込みに失敗した場合は
# 非 0 で終了する。URL が空の場合と gh の失敗時は state ファイルに触れない。書き込みは一時ファイル
# 経由なので、失敗しても既存の state ファイルは残る。
# CLAUDE_CODE_SESSION_ID が空または不正な場合は state を書かず、警告を出して PR URL だけを出力し 0 で終了する。

set -uo pipefail

REPO="${1:-}"
SESSION_ID="${CLAUDE_CODE_SESSION_ID:-}"
DATA_DIR=~/.claude/data

if ! mkdir -p "$DATA_DIR" || ! chmod 700 "$DATA_DIR"; then
  echo "ERROR: failed to prepare ~/.claude/data" >&2
  exit 1
fi

PR_VIEW_ARGS=()
if [ -n "$REPO" ]; then
  BRANCH=$(git branch --show-current)
  if [ -z "$BRANCH" ]; then
    echo "ERROR: cannot determine the current branch (detached HEAD?)" >&2
    exit 1
  fi
  if ! ORIGIN_REPO=$(gh-pr-target-repo.sh --origin) || [ -z "${ORIGIN_REPO%%/*}" ]; then
    echo "ERROR: cannot resolve the owner of origin" >&2
    exit 1
  fi
  PR_VIEW_ARGS=("${ORIGIN_REPO%%/*}:$BRANCH" --repo "$REPO")
fi

if ! PR_URL=$(gh pr view ${PR_VIEW_ARGS[@]+"${PR_VIEW_ARGS[@]}"} --json url -q .url); then
  echo "ERROR: gh pr view failed, not writing session state" >&2
  exit 1
fi
if [ -z "$PR_URL" ]; then
  echo "ERROR: gh pr view returned an empty URL, not writing session state" >&2
  exit 1
fi

if [[ ! "$SESSION_ID" =~ ^[A-Za-z0-9._-]+$ ]]; then
  echo "WARNING: CLAUDE_CODE_SESSION_ID is empty or contains invalid characters (got: '${SESSION_ID}'), not writing session state" >&2
  echo "$PR_URL"
  exit 0
fi

STATE_FILE="$DATA_DIR/session-state-${SESSION_ID}.json"
TMP_FILE="${STATE_FILE}.tmp.$$"

if ! jq -n --arg pr_url "$PR_URL" --arg session_id "$SESSION_ID" --argjson timestamp "$(date +%s)" \
    '{"pr_url": $pr_url, "session_id": $session_id, "timestamp": $timestamp}' \
    > "$TMP_FILE"; then
  echo "ERROR: failed to write $STATE_FILE" >&2
  rm -f "$TMP_FILE"
  exit 1
fi

if ! chmod 600 "$TMP_FILE"; then
  echo "ERROR: failed to chmod $TMP_FILE" >&2
  rm -f "$TMP_FILE"
  exit 1
fi

if ! mv "$TMP_FILE" "$STATE_FILE"; then
  echo "ERROR: failed to move $TMP_FILE to $STATE_FILE" >&2
  rm -f "$TMP_FILE"
  exit 1
fi

# hook 側の TTL (24 時間) と同じ長さを過ぎた他セッションの state を掃除する。失敗しても書き込みは成功扱いにする。
find "$DATA_DIR" -maxdepth 1 -name 'session-state-*.json' -mmin +1440 -delete ||
  echo "WARNING: failed to remove stale session state files" >&2

# 呼び出し元がそのまま使えるよう、書き込んだ PR URL を標準出力にも出す。
echo "$PR_URL"
