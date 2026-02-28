#!/usr/bin/env bash

set -euo pipefail

# 引数チェック
if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <PR_NUMBER>" >&2
  exit 1
fi

PR_NUMBER="$1"

# PR 番号の妥当性チェック
if ! [[ "$PR_NUMBER" =~ ^[0-9]+$ ]]; then
  echo "Error: PR_NUMBER must be a number" >&2
  exit 1
fi

# ディレクトリ作成
LOG_DIR="$HOME/.claude/logs"
LOCK_DIR="$HOME/.claude/locks"
mkdir -p "$LOG_DIR" "$LOCK_DIR"

LOG_FILE="$LOG_DIR/wait-copilot-review-${PR_NUMBER}.log"
LOCK_FILE="$LOCK_DIR/wait-copilot-review-${PR_NUMBER}.lock"

# ロックファイルのクリーンアップを設定
# shellcheck disable=SC2317
cleanup() {
  rm -f "$LOCK_FILE"
}
trap cleanup EXIT

# ロック取得（既に実行中の場合はエラー）
exec 200>"$LOCK_FILE"
if ! flock -n 200; then
  echo "Already running for PR #${PR_NUMBER}" >&2
  exit 1
fi

# ログ開始
{
  echo "=== $(date -Iseconds) ==="
  echo "Waiting for Copilot review on PR #${PR_NUMBER}"
} >> "$LOG_FILE"

# リポジトリ情報取得
OWNER=$(gh repo view --json owner --jq '.owner.login')
REPO=$(gh repo view --json name --jq '.name')

echo "Repository: ${OWNER}/${REPO}" >> "$LOG_FILE"

# 待機パラメータ
MAX_WAIT=1800  # 30 分
INTERVAL=30    # 30 秒
ELAPSED=0

# GraphQL クエリ
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

# jq フィルタ（Copilot レビューを抽出）
JQ_FILTER='[.data.repository.pullRequest.reviews.nodes[] | select(.author.__typename == "Bot" and (.author.login | contains("copilot")) and (.state == "COMMENTED" or .state == "APPROVED") and .submittedAt != null)] | length'

# tmux セッションに通知を送る関数
notify_tmux() {
  local message="$1"
  local session
  # tmux セッションが存在するか確認
  if ! session=$(tmux display-message -p '#{session_name}' 2>/dev/null); then
    return 0
  fi
  tmux send-keys -t "$session" "$message" && sleep 3 && tmux send-keys -t "$session" Enter
}

# Discord 通知を送る関数
notify_discord() {
  local title="$1"
  local desc="$2"
  local SCRIPT_DIR="$HOME/.claude/scripts/completion-notify"
  if [[ -x "$SCRIPT_DIR/send-discord-notification.sh" ]]; then
    local payload
    payload=$(jq -n \
      --arg title "$title" \
      --arg desc "$desc" \
      --arg url "https://github.com/${OWNER}/${REPO}/pull/${PR_NUMBER}" \
      '{
        embeds: [{
          title: $title,
          description: $desc,
          url: $url,
          color: 3447003
        }]
      }')
    printf '%s\n' "${payload}" | "$SCRIPT_DIR/send-discord-notification.sh" >> "$LOG_FILE" 2>&1 &
    echo "Discord notification sent" >> "$LOG_FILE"
  fi
}

# レビュー数を取得する関数
get_review_count() {
  gh api graphql \
    -f owner="$OWNER" \
    -f repo="$REPO" \
    -F number="$PR_NUMBER" \
    -f query="$GRAPHQL_QUERY" \
    --jq "$JQ_FILTER" 2>> "$LOG_FILE"
}

# 初回レビュー数を取得
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

# スクリプト起動前に既に Copilot レビューが存在する場合は即座に通知
if [ "$INITIAL_REVIEWS" -gt 0 ]; then
  echo "Copilot review already exists (${INITIAL_REVIEWS} reviews)" >> "$LOG_FILE"
  MSG="PR #${PR_NUMBER} に Copilot レビューが既に投稿されています（${INITIAL_REVIEWS} 件）。対応してください。"
  echo "✅ ${MSG}"
  echo "📝 ログ: ${LOG_FILE}"
  notify_discord "GitHub Copilot Review Already Posted" "${MSG}"
  notify_tmux "${MSG}"
  exit 0
fi

# ポーリングループ
while [ $ELAPSED -lt $MAX_WAIT ]; do
  sleep $INTERVAL
  ELAPSED=$((ELAPSED + INTERVAL))

  # 現在のレビュー数を確認
  if ! CURRENT_REVIEWS=$(get_review_count); then
    echo "[$ELAPSED s] Warning: Failed to get current review count" >> "$LOG_FILE"
    continue
  fi

  if [[ -z "$CURRENT_REVIEWS" ]]; then
    echo "[$ELAPSED s] Warning: Failed to get current review count" >> "$LOG_FILE"
    continue
  fi

  echo "[$ELAPSED s] Current Copilot reviews: ${CURRENT_REVIEWS}" >> "$LOG_FILE"

  if [ "$CURRENT_REVIEWS" -gt "$INITIAL_REVIEWS" ]; then
    NEW_REVIEWS=$((CURRENT_REVIEWS - INITIAL_REVIEWS))
    echo "Detected ${NEW_REVIEWS} new Copilot review(s)!" >> "$LOG_FILE"

    MSG="PR #${PR_NUMBER} に Copilot レビューが ${NEW_REVIEWS} 件投稿されました。対応してください。"
    echo "✅ ${MSG}"
    echo "📝 ログ: ${LOG_FILE}"
    notify_discord "GitHub Copilot Review Detected" "${MSG}"
    notify_tmux "${MSG}"
    exit 0
  fi
done

# タイムアウト
TIMEOUT_MSG="PR #${PR_NUMBER}: ${MAX_WAIT} 秒以内に Copilot レビューが投稿されませんでした。手動で確認してください。"
echo "Timeout: No new Copilot reviews detected within ${MAX_WAIT}s" >> "$LOG_FILE"
echo "⏱️ タイムアウト: ${TIMEOUT_MSG}"
echo "📝 ログ: ${LOG_FILE}"
notify_tmux "${TIMEOUT_MSG}"
exit 0
