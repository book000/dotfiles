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
  "home/dot_codex/scripts/completion-notify/executable_notify-completion.sh"
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

echo "Testing Codex completion notification behavior..."
TEST_DIR=$(mktemp -d)
cleanup() {
  rm -rf "$TEST_DIR"
}
trap cleanup EXIT

cp home/dot_codex/scripts/completion-notify/executable_notify-completion.sh "$TEST_DIR/notify-completion.sh"
cat > "$TEST_DIR/.env" <<'EOF'
export DISCORD_WEBHOOK_URL="https://example.invalid/webhook"
export MENTION_USER_ID="1234567890"
EOF
cat > "$TEST_DIR/send-discord-notification.sh" <<'EOF'
#!/bin/bash
cat > "$TEST_CAPTURE_FILE"
EOF
chmod +x "$TEST_DIR/send-discord-notification.sh"

TEST_CAPTURE_FILE="$TEST_DIR/payload.json"
HOOK_OUTPUT=$(
  printf '%s' '{"session_id":"session-1","cwd":"/tmp/work","model":"gpt-5.4","last_assistant_message":"done"}' \
    | TEST_CAPTURE_FILE="$TEST_CAPTURE_FILE" bash "$TEST_DIR/notify-completion.sh"
)

if [[ "$HOOK_OUTPUT" != '{"continue":true}' ]]; then
  echo "❌ Codex completion notification did not emit the expected continue payload"
  FAILED=1
else
  echo "✅ Codex completion notification emitted the expected continue payload"
fi

sleep 1

if ! [[ -f "$TEST_CAPTURE_FILE" ]]; then
  echo "❌ Codex completion notification did not invoke the Discord sender"
  FAILED=1
else
  if ! grep -Fq 'Codex CLI Finished' "$TEST_CAPTURE_FILE"; then
    echo "❌ Codex completion notification payload did not include the completion content"
    FAILED=1
  else
    echo "✅ Codex completion notification payload included the completion content"
  fi

  if ! grep -Fq 'session-1' "$TEST_CAPTURE_FILE"; then
    echo "❌ Codex completion notification payload did not include the session id"
    FAILED=1
  else
    echo "✅ Codex completion notification payload included the session id"
  fi
fi

if [ $FAILED -eq 0 ]; then
  echo "✅ All notification script tests passed"
else
  echo "❌ Some notification script tests failed"
  exit 1
fi
