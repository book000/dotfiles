#!/bin/bash
# Discord 通知スクリプトのユニットテスト

set -euo pipefail

echo "Testing Discord notification scripts..."

FAILED=0

# テスト対象の通知スクリプト
NOTIFICATION_SCRIPTS=(
  "home/dot_claude/scripts/completion-notify/executable_send-discord-notification.sh"
  "home/dot_claude/scripts/completion-notify/executable_notify-completion.sh"
  "home/dot_claude/scripts/completion-notify/executable_notify-notification.sh"
  "home/dot_claude/scripts/completion-notify/executable_notify-permission-request.sh"
  "home/dot_claude/scripts/completion-notify/executable_notify-user-prompt-submit.sh"
  "home/dot_claude/scripts/limit-unlocked/executable_check-notify.sh"
  "home/dot_codex/scripts/completion-notify/executable_send-discord-notification.sh"
)

# 各通知スクリプトの構文チェック
for script in "${NOTIFICATION_SCRIPTS[@]}"; do
  if [ ! -f "$script" ]; then
    echo "⚠️  Notification script not found: $script"
    continue
  fi

  echo "Testing script: $script"

  # bash 構文チェック
  if ! bash -n "$script"; then
    echo "❌ Syntax error in script: $script"
    FAILED=1
  else
    echo "✅ Syntax OK: $script"
  fi
done

if [ $FAILED -eq 0 ]; then
  echo "✅ All notification script tests passed"
else
  echo "❌ Some notification script tests failed"
  exit 1
fi
