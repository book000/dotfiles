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

echo "Testing check-notify.sh is safely sourceable (no side effects)..."
TEST_HOME=$(mktemp -d)
if ! (
  HOME="$TEST_HOME" bash -c '
    source "'"$PWD"'/home/dot_claude/scripts/limit-unlocked/executable_check-notify.sh"
    if declare -p STATE_FILE >/dev/null 2>&1; then
      echo "STATE_FILE should not be set when sourced" >&2
      exit 1
    fi
    if ! declare -F resolve_jsonl_path >/dev/null 2>&1; then
      echo "resolve_jsonl_path should be defined after sourcing" >&2
      exit 1
    fi
  '
); then
  echo "❌ check-notify.sh executed main logic (or failed) when sourced"
  FAILED=1
else
  echo "✅ check-notify.sh only defines functions when sourced"
fi
if [ -d "$TEST_HOME/.claude/scripts/limit-unlocked/data" ]; then
  echo "❌ check-notify.sh created state directory as a side effect of sourcing"
  FAILED=1
fi
rm -rf "$TEST_HOME"

echo "Testing resolve_config_dir resolves the mocked claude process's CLAUDE_CONFIG_DIR..."
TEST_HOME=$(mktemp -d)
TEST_BIN_DIR=$(mktemp -d)
mkdir -p "$TEST_HOME/.claude/sessions"

CLAUDE_CONFIG_DIR="$TEST_HOME/.claude" sleep 60 &
FAKE_CLAUDE_PID=$!
echo '{}' > "$TEST_HOME/.claude/sessions/${FAKE_CLAUDE_PID}.json"

cat > "$TEST_BIN_DIR/tmux" <<EOF
#!/bin/bash
if [[ "\$1" == "display-message" ]]; then
  echo "12345"
  exit 0
fi
exit 1
EOF
chmod +x "$TEST_BIN_DIR/tmux"

cat > "$TEST_BIN_DIR/pgrep" <<EOF
#!/bin/bash
echo "$FAKE_CLAUDE_PID"
EOF
chmod +x "$TEST_BIN_DIR/pgrep"

RESULT=$(
  PATH="$TEST_BIN_DIR:$PATH" HOME="$TEST_HOME" bash -c '
    source "'"$PWD"'/home/dot_claude/scripts/limit-unlocked/executable_check-notify.sh"
    resolve_config_dir "dummy-session"
  '
)

kill "$FAKE_CLAUDE_PID" 2>/dev/null || true
wait "$FAKE_CLAUDE_PID" 2>/dev/null || true

if [[ "$RESULT" != "$TEST_HOME/.claude" ]]; then
  echo "❌ resolve_config_dir did not resolve the mocked claude process's CLAUDE_CONFIG_DIR (got: '$RESULT')"
  FAILED=1
else
  echo "✅ resolve_config_dir resolved the mocked claude process's CLAUDE_CONFIG_DIR"
fi
rm -rf "$TEST_HOME" "$TEST_BIN_DIR"

echo "Testing fetch_usage_status..."
TEST_HOME=$(mktemp -d)
TEST_BIN_DIR=$(mktemp -d)
TEST_CONFIG_DIR="$TEST_HOME/.claude"
mkdir -p "$TEST_CONFIG_DIR"

FUTURE_MS=$(( ($(date +%s) + 3600) * 1000 ))
cat > "$TEST_CONFIG_DIR/.credentials.json" <<EOF
{"claudeAiOauth": {"accessToken": "dummy-token", "expiresAt": $FUTURE_MS}}
EOF

cat > "$TEST_BIN_DIR/curl" <<'EOF'
#!/bin/bash
printf '%s\n200\n' '{"five_hour":{"utilization":42},"seven_day":{"utilization":10}}'
EOF
chmod +x "$TEST_BIN_DIR/curl"

RESULT=$(
  PATH="$TEST_BIN_DIR:$PATH" bash -c '
    source "'"$PWD"'/home/dot_claude/scripts/limit-unlocked/executable_check-notify.sh"
    fetch_usage_status "'"$TEST_CONFIG_DIR"'"
  '
)

if [[ "$RESULT" != $'42\t10' ]]; then
  echo "❌ fetch_usage_status did not parse a successful response (got: '$RESULT')"
  FAILED=1
else
  echo "✅ fetch_usage_status parsed a successful response"
fi

echo "Testing fetch_usage_status fails safely on non-200 response..."
cat > "$TEST_BIN_DIR/curl" <<'EOF'
#!/bin/bash
printf '%s\n401\n' '{"error":"unauthorized"}'
EOF
chmod +x "$TEST_BIN_DIR/curl"

if PATH="$TEST_BIN_DIR:$PATH" bash -c '
    source "'"$PWD"'/home/dot_claude/scripts/limit-unlocked/executable_check-notify.sh"
    fetch_usage_status "'"$TEST_CONFIG_DIR"'"
  ' >/tmp/fetch_usage_status_401_out 2>/dev/null; then
  echo "❌ fetch_usage_status should fail on a non-200 response"
  FAILED=1
elif [ -s /tmp/fetch_usage_status_401_out ]; then
  echo "❌ fetch_usage_status printed output on a non-200 response"
  FAILED=1
else
  echo "✅ fetch_usage_status failed safely on a non-200 response"
fi
rm -f /tmp/fetch_usage_status_401_out

echo "Testing fetch_usage_status fails safely on missing utilization field..."
cat > "$TEST_BIN_DIR/curl" <<'EOF'
#!/bin/bash
printf '%s\n200\n' '{"five_hour":{"utilization":null},"seven_day":{"utilization":10}}'
EOF
chmod +x "$TEST_BIN_DIR/curl"

if PATH="$TEST_BIN_DIR:$PATH" bash -c '
    source "'"$PWD"'/home/dot_claude/scripts/limit-unlocked/executable_check-notify.sh"
    fetch_usage_status "'"$TEST_CONFIG_DIR"'"
  ' >/dev/null 2>/dev/null; then
  echo "❌ fetch_usage_status should fail when five_hour.utilization is null"
  FAILED=1
else
  echo "✅ fetch_usage_status failed safely when five_hour.utilization is null"
fi

echo "Testing fetch_usage_status fails safely on out-of-range utilization..."
cat > "$TEST_BIN_DIR/curl" <<'EOF'
#!/bin/bash
printf '%s\n200\n' '{"five_hour":{"utilization":150},"seven_day":{"utilization":10}}'
EOF
chmod +x "$TEST_BIN_DIR/curl"

if PATH="$TEST_BIN_DIR:$PATH" bash -c '
    source "'"$PWD"'/home/dot_claude/scripts/limit-unlocked/executable_check-notify.sh"
    fetch_usage_status "'"$TEST_CONFIG_DIR"'"
  ' >/tmp/fetch_usage_status_range_out 2>/dev/null; then
  echo "❌ fetch_usage_status should fail when five_hour.utilization is out of range (>100)"
  FAILED=1
elif [ -s /tmp/fetch_usage_status_range_out ]; then
  echo "❌ fetch_usage_status printed output on an out-of-range utilization"
  FAILED=1
else
  echo "✅ fetch_usage_status failed safely on an out-of-range utilization"
fi
rm -f /tmp/fetch_usage_status_range_out

echo "Testing fetch_usage_status fails safely on expired token without calling curl..."
PAST_MS=$(( ($(date +%s) - 3600) * 1000 ))
cat > "$TEST_CONFIG_DIR/.credentials.json" <<EOF
{"claudeAiOauth": {"accessToken": "dummy-token", "expiresAt": $PAST_MS}}
EOF
cat > "$TEST_BIN_DIR/curl" <<'EOF'
#!/bin/bash
echo "curl should not have been called" >&2
exit 1
EOF
chmod +x "$TEST_BIN_DIR/curl"

if PATH="$TEST_BIN_DIR:$PATH" bash -c '
    source "'"$PWD"'/home/dot_claude/scripts/limit-unlocked/executable_check-notify.sh"
    fetch_usage_status "'"$TEST_CONFIG_DIR"'"
  ' >/dev/null 2>/dev/null; then
  echo "❌ fetch_usage_status should fail on an expired token"
  FAILED=1
else
  echo "✅ fetch_usage_status failed safely on an expired token (curl not called)"
fi

rm -rf "$TEST_HOME" "$TEST_BIN_DIR"

echo "Testing usage_check_allowed / record_usage_checked throttling..."
TEST_HOME=$(mktemp -d)

RESULT=$(
  HOME="$TEST_HOME" bash -c '
    source "'"$PWD"'/home/dot_claude/scripts/limit-unlocked/executable_check-notify.sh"
    if usage_check_allowed "/fake/config-dir"; then
      echo "allowed_initially=yes"
    else
      echo "allowed_initially=no"
    fi

    record_usage_checked "/fake/config-dir"

    if usage_check_allowed "/fake/config-dir"; then
      echo "allowed_immediately_after=yes"
    else
      echo "allowed_immediately_after=no"
    fi

    # 最終チェック時刻を31分前に書き換える
    file=$(usage_last_checked_file)
    old_epoch=$(( $(date +%s) - 1860 ))
    printf "/fake/config-dir\t%s\n" "$old_epoch" > "$file"

    if usage_check_allowed "/fake/config-dir"; then
      echo "allowed_after_31min=yes"
    else
      echo "allowed_after_31min=no"
    fi
  '
)

if ! grep -q '^allowed_initially=yes$' <<< "$RESULT"; then
  echo "❌ usage_check_allowed did not allow the first check for a new config_dir"
  FAILED=1
else
  echo "✅ usage_check_allowed allowed the first check for a new config_dir"
fi

if ! grep -q '^allowed_immediately_after=no$' <<< "$RESULT"; then
  echo "❌ usage_check_allowed did not throttle an immediate re-check"
  FAILED=1
else
  echo "✅ usage_check_allowed throttled an immediate re-check"
fi

if ! grep -q '^allowed_after_31min=yes$' <<< "$RESULT"; then
  echo "❌ usage_check_allowed did not allow a re-check after 31 minutes"
  FAILED=1
else
  echo "✅ usage_check_allowed allowed a re-check after 31 minutes"
fi

rm -rf "$TEST_HOME"

if [ $FAILED -eq 0 ]; then
  echo "✅ All notification script tests passed"
else
  echo "❌ Some notification script tests failed"
  exit 1
fi
