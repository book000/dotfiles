#!/usr/bin/env bash

set -euo pipefail

# 引数チェック
if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <PR_NUMBER_OR_URL>" >&2
  exit 1
fi

PR_ARG="$1"
DISCORD_MENTION_PREFIX=""

parse_remote_url() {
  local remote_name="$1"
  local remote_url

  remote_url=$(git remote get-url "$remote_name" 2>/dev/null || true)
  if [[ -z "$remote_url" ]]; then
    return 1
  fi

  case "$remote_url" in
    git@github.com:*)
      remote_url="${remote_url#git@github.com:}"
      ;;
    https://github.com/*)
      remote_url="${remote_url#https://github.com/}"
      ;;
    ssh://git@github.com/*)
      remote_url="${remote_url#ssh://git@github.com/}"
      ;;
    *)
      return 1
      ;;
  esac

  remote_url="${remote_url%.git}"

  if [[ "$remote_url" != */* ]]; then
    return 1
  fi

  OWNER="${remote_url%%/*}"
  REPO="${remote_url##*/}"
  return 0
}

parse_pr_url() {
  local pr_url="$1"

  if [[ "$pr_url" =~ ^https://github\.com/([^/]+)/([^/]+)/pull/([0-9]+)(/)?([?#].*)?$ ]]; then
    OWNER="${BASH_REMATCH[1]}"
    REPO="${BASH_REMATCH[2]}"
    PR_NUMBER="${BASH_REMATCH[3]}"
    return 0
  fi

  return 1
}

resolve_repo_from_preferred_remote() {
  local helper
  local preferred_repo

  helper="$HOME/bin/gh-pr-target-repo.sh"
  if [[ -x "$helper" ]]; then
    preferred_repo=$("$helper" 2>/dev/null || true)
    if [[ -n "$preferred_repo" && "$preferred_repo" == */* ]]; then
      OWNER="${preferred_repo%%/*}"
      REPO="${preferred_repo##*/}"
      return 0
    fi
  fi

  for remote_name in upstream origin; do
    if parse_remote_url "$remote_name"; then
      return 0
    fi
  done

  return 1
}

load_codex_mention_prefix() {
  local env_file="$HOME/.env"
  local mention_user_id=""

  if [[ ! -f "$env_file" ]]; then
    return 0
  fi

  mention_user_id="$(
    (
      set +u
      # shellcheck source=/dev/null
      source "$env_file" >/dev/null 2>&1
      printf '%s' "${DISCORD_CODEX_MENTION_USER_ID:-}"
    ) 2>/dev/null || true
  )"

  if [[ -n "$mention_user_id" ]]; then
    DISCORD_MENTION_PREFIX="<@${mention_user_id}> "
  fi
}

if [[ "$PR_ARG" =~ ^[0-9]+$ ]]; then
  PR_NUMBER="$PR_ARG"
  if ! resolve_repo_from_preferred_remote; then
    OWNER=$(gh repo view --json owner --jq '.owner.login')
    REPO=$(gh repo view --json name --jq '.name')
  fi
elif ! parse_pr_url "$PR_ARG"; then
  echo "Error: PR_NUMBER_OR_URL must be a PR number or GitHub PR URL" >&2
  exit 1
fi

load_codex_mention_prefix

LOG_DIR="$HOME/.codex/logs"
LOCK_DIR="$HOME/.codex/locks"
mkdir -p "$LOG_DIR" "$LOCK_DIR"

REPO_SLUG="${OWNER}-${REPO}"
LOG_FILE="$LOG_DIR/wait-copilot-review-${REPO_SLUG}-${PR_NUMBER}.log"
LOCK_FILE="$LOCK_DIR/wait-copilot-review-${REPO_SLUG}-${PR_NUMBER}.lock"

# shellcheck disable=SC2317
cleanup() {
  rm -f "$LOCK_FILE"
}
trap cleanup EXIT

exec 200>"$LOCK_FILE"
if ! flock -n 200; then
  echo "Already running for PR #${PR_NUMBER}" >&2
  exit 1
fi

{
  echo "=== $(date -Iseconds) ==="
  echo "Waiting for Copilot review on PR #${PR_NUMBER}"
} >> "$LOG_FILE"

MAX_WAIT=1800
INTERVAL=30
ELAPSED=0

# shellcheck disable=SC2016
GRAPHQL_QUERY='query($owner: String!, $repo: String!, $number: Int!) {
  repository(owner: $owner, name: $repo) {
    pullRequest(number: $number) {
      reviews(first: 100) {
        nodes {
          author {
            login
            __typename
          }
          state
          submittedAt
        }
      }
    }
  }
}'

JQ_FILTER='[.data.repository.pullRequest.reviews.nodes[] | select(.author.__typename == "Bot" and (.author.login | ascii_downcase | contains("copilot")) and (.state == "COMMENTED" or .state == "APPROVED" or .state == "CHANGES_REQUESTED") and .submittedAt != null)] | length'

notify_tmux() {
  local message="$1"
  local session

  if ! session=$(tmux display-message -p '#{session_name}' 2>/dev/null); then
    return 0
  fi

  tmux send-keys -t "${session}:" "$message" && sleep 3 && tmux send-keys -t "${session}:" Enter
}

notify_tmux_status() {
  local message="$1"
  local session

  if ! session=$(tmux display-message -p '#{session_name}' 2>/dev/null); then
    return 0
  fi

  tmux display-message -t "${session}:" "$message" 2>/dev/null || tmux display-message "$message" 2>/dev/null || true
}

notify_discord() {
  local title="$1"
  local desc="$2"
  local script_dir="$HOME/.codex/scripts/completion-notify"

  if [[ ! -x "$script_dir/send-discord-notification.sh" ]]; then
    return 0
  fi

  local payload
  payload=$(jq -n \
    --arg content "${DISCORD_MENTION_PREFIX}Codex CLI Notification" \
    --arg title "$title" \
    --arg desc "$desc" \
    --arg url "https://github.com/${OWNER}/${REPO}/pull/${PR_NUMBER}" \
    '{
      content: $content,
      embeds: [{
        title: $title,
        description: $desc,
        url: $url,
        color: 3447003
      }]
    }')
  printf '%s\n' "$payload" | "$script_dir/send-discord-notification.sh" >> "$LOG_FILE" 2>&1 &
}

get_review_count() {
  gh api graphql \
    -f owner="$OWNER" \
    -f repo="$REPO" \
    -F number="$PR_NUMBER" \
    -f query="$GRAPHQL_QUERY" \
    --jq "$JQ_FILTER" 2>> "$LOG_FILE"
}

if ! INITIAL_REVIEWS=$(get_review_count); then
  echo "Error: Failed to get initial review count" >> "$LOG_FILE"
  echo "Error: Failed to get initial review count" >&2
  exit 1
fi

if [[ -z "$INITIAL_REVIEWS" ]]; then
  echo "Error: Failed to get initial review count" >> "$LOG_FILE"
  echo "Error: Failed to get initial review count" >&2
  exit 1
fi

echo "Initial Copilot reviews: ${INITIAL_REVIEWS}" >> "$LOG_FILE"

if [[ "$INITIAL_REVIEWS" -gt 0 ]]; then
  DISCORD_MSG="PR #${PR_NUMBER} に Copilot レビューが既に投稿されています（${INITIAL_REVIEWS} 件）。"
  TMUX_CMD="\$handle-pr-reviews https://github.com/${OWNER}/${REPO}/pull/${PR_NUMBER}"
  echo "$DISCORD_MSG" >> "$LOG_FILE"
  notify_discord "GitHub Copilot Review Already Posted" "$DISCORD_MSG"
  notify_tmux "$TMUX_CMD"
  exit 0
fi

while [[ $ELAPSED -lt $MAX_WAIT ]]; do
  sleep $INTERVAL
  ELAPSED=$((ELAPSED + INTERVAL))

  if ! CURRENT_REVIEWS=$(get_review_count); then
    echo "[$ELAPSED s] Warning: Failed to get current review count" >> "$LOG_FILE"
    continue
  fi

  if [[ -z "$CURRENT_REVIEWS" ]]; then
    echo "[$ELAPSED s] Warning: Failed to get current review count" >> "$LOG_FILE"
    continue
  fi

  echo "[$ELAPSED s] Current Copilot reviews: ${CURRENT_REVIEWS}" >> "$LOG_FILE"

  if [[ "$CURRENT_REVIEWS" -gt "$INITIAL_REVIEWS" ]]; then
    NEW_REVIEWS=$((CURRENT_REVIEWS - INITIAL_REVIEWS))
    DISCORD_MSG="PR #${PR_NUMBER} に Copilot レビューが ${NEW_REVIEWS} 件投稿されました。"
    TMUX_CMD="\$handle-pr-reviews https://github.com/${OWNER}/${REPO}/pull/${PR_NUMBER}"
    echo "$DISCORD_MSG" >> "$LOG_FILE"
    notify_discord "GitHub Copilot Review Detected" "$DISCORD_MSG"
    notify_tmux "$TMUX_CMD"
    exit 0
  fi
done

TIMEOUT_MSG="PR #${PR_NUMBER}: ${MAX_WAIT} 秒以内に Copilot レビューが投稿されませんでした。手動で確認してください。"
echo "Timeout: No new Copilot reviews detected within ${MAX_WAIT}s" >> "$LOG_FILE"
notify_tmux_status "$TIMEOUT_MSG"
exit 0
