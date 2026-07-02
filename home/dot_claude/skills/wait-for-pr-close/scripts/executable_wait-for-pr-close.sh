#!/bin/bash

set -euo pipefail

# 引数チェック（PR_NUMBER は必須、--repo は任意）
if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <PR_NUMBER> [--repo <owner>/<repo>]" >&2
  exit 1
fi

PR_NUMBER="$1"
shift

REPO_ARG=""
REPO_SLUG=""
if [[ $# -ge 2 && "$1" == "--repo" ]]; then
  REPO_SLUG="$2"
  REPO_ARG="--repo"
fi

# PR 番号の妥当性チェック
if ! [[ "$PR_NUMBER" =~ ^[0-9]+$ ]]; then
  echo "Error: PR_NUMBER must be a number" >&2
  exit 1
fi

# ディレクトリ作成
LOG_DIR="$HOME/.claude/logs"
LOCK_DIR="$HOME/.claude/locks"
mkdir -p "$LOG_DIR" "$LOCK_DIR"

LOG_FILE="$LOG_DIR/wait-pr-close-${PR_NUMBER}.log"
LOCK_FILE="$LOCK_DIR/wait-pr-close-${PR_NUMBER}.lock"

# ロック取得（既に実行中の場合はエラー）
exec 200>"$LOCK_FILE"
if ! flock -n 200; then
  echo "Already running for PR #${PR_NUMBER}" >&2
  exit 1
fi

# ロックファイルのクリーンアップを設定
# ロック取得後に trap を張る。取得前に張ると、フロック競争に負けた側の
# exit で勝った側のロックファイルが削除され、後続の別インスタンスが
# 新しい inode に対して flock に成功し、多重起動排他が破られてしまう。
# shellcheck disable=SC2317
cleanup() {
  rm -f "$LOCK_FILE"
}
trap cleanup EXIT

# ログ開始
{
  echo "=== $(date -Iseconds) ==="
  echo "Waiting for PR #${PR_NUMBER} to be merged or closed"
} >> "$LOG_FILE"

# リポジトリ情報取得（--repo 指定があればそれを使う。なければローカル origin）
if [[ -n "$REPO_SLUG" ]]; then
  OWNER="${REPO_SLUG%%/*}"
  REPO="${REPO_SLUG##*/}"
else
  OWNER=$(gh repo view --json owner --jq '.owner.login')
  REPO=$(gh repo view --json name --jq '.name')
fi

echo "Repository: ${OWNER}/${REPO}" >> "$LOG_FILE"

# 待機パラメータ（環境変数で上書き可能。未設定時のデフォルトは
# WAIT_FOR_PR_CLOSE_MAX_WAIT=86400（24 時間）、WAIT_FOR_PR_CLOSE_INTERVAL=30（30 秒））
MAX_WAIT="${WAIT_FOR_PR_CLOSE_MAX_WAIT:-86400}"
INTERVAL="${WAIT_FOR_PR_CLOSE_INTERVAL:-30}"
ELAPSED=0

# 待機パラメータの妥当性チェック（不正値をサイレントに無視しない）
if ! [[ "$MAX_WAIT" =~ ^[0-9]+$ ]] || [[ "$MAX_WAIT" -le 0 ]]; then
  echo "Error: WAIT_FOR_PR_CLOSE_MAX_WAIT must be a positive integer" >&2
  exit 1
fi
if ! [[ "$INTERVAL" =~ ^[0-9]+$ ]] || [[ "$INTERVAL" -le 0 ]]; then
  echo "Error: WAIT_FOR_PR_CLOSE_INTERVAL must be a positive integer" >&2
  exit 1
fi

# PR 状態を取得する関数
get_pr_state() {
  if [[ -n "$REPO_ARG" ]]; then
    gh pr view "$PR_NUMBER" --repo "$REPO_SLUG" --json state -q .state 2>> "$LOG_FILE"
  else
    gh pr view "$PR_NUMBER" --json state -q .state 2>> "$LOG_FILE"
  fi
}

# tmux セッションに通知を送る関数
notify_tmux() {
  local message="$1"
  local session
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

# 初回状態を取得
if ! INITIAL_STATE=$(get_pr_state); then
  echo "Error: Failed to get initial PR state" >> "$LOG_FILE"
  echo "Error: Failed to get initial PR state" >&2
  exit 1
fi

echo "Initial state: ${INITIAL_STATE}" >> "$LOG_FILE"

# クリーンアップ呼び出し用のターゲット文字列を決定する
# 新規セッションで起動される pr-cleanup はローカル origin の情報しか持たないため、
# --repo でクロスリポジトリを指定した場合は PR 番号だけでは対象を解決できない
if [[ -n "$REPO_SLUG" ]]; then
  CLEANUP_TARGET="https://github.com/${OWNER}/${REPO}/pull/${PR_NUMBER}"
else
  CLEANUP_TARGET="$PR_NUMBER"
fi

# 起動時点で既に MERGED/CLOSED の場合は即座に通知
if [[ "$INITIAL_STATE" == "MERGED" || "$INITIAL_STATE" == "CLOSED" ]]; then
  echo "PR is already ${INITIAL_STATE}" >> "$LOG_FILE"
  DISCORD_MSG="PR #${PR_NUMBER} は既に ${INITIAL_STATE} 状態です。"
  TMUX_CMD="/pr-cleanup ${CLEANUP_TARGET}"
  echo "✅ ${DISCORD_MSG}"
  echo "📝 ログ: ${LOG_FILE}"
  notify_discord "PR Already ${INITIAL_STATE}" "${DISCORD_MSG}"
  notify_tmux "${TMUX_CMD}"
  exit 0
fi

# ポーリングループ
while [ "$ELAPSED" -lt "$MAX_WAIT" ]; do
  sleep "$INTERVAL"
  ELAPSED=$((ELAPSED + INTERVAL))

  if ! CURRENT_STATE=$(get_pr_state); then
    echo "[$ELAPSED s] Warning: Failed to get current PR state" >> "$LOG_FILE"
    continue
  fi

  echo "[$ELAPSED s] Current state: ${CURRENT_STATE}" >> "$LOG_FILE"

  if [[ "$CURRENT_STATE" == "MERGED" || "$CURRENT_STATE" == "CLOSED" ]]; then
    echo "PR transitioned to ${CURRENT_STATE}" >> "$LOG_FILE"

    DISCORD_MSG="PR #${PR_NUMBER} が ${CURRENT_STATE} されました。"
    TMUX_CMD="/pr-cleanup ${CLEANUP_TARGET}"
    echo "✅ ${DISCORD_MSG}"
    echo "📝 ログ: ${LOG_FILE}"
    notify_discord "PR ${CURRENT_STATE}" "${DISCORD_MSG}"
    notify_tmux "${TMUX_CMD}"
    exit 0
  fi
done

# タイムアウト
TIMEOUT_MSG="PR #${PR_NUMBER}: ${MAX_WAIT} 秒以内にマージ/クローズが検知されませんでした。手動で確認してください。"
echo "Timeout: No merge/close detected within ${MAX_WAIT}s" >> "$LOG_FILE"
echo "⏱️ タイムアウト: ${TIMEOUT_MSG}"
echo "📝 ログ: ${LOG_FILE}"
notify_tmux "${TIMEOUT_MSG}"
exit 0
