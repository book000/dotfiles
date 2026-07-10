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

echo "Testing fetch_usage_status does not expose the OAuth token via curl's argv..."
FUTURE_MS=$(( ($(date +%s) + 3600) * 1000 ))
cat > "$TEST_CONFIG_DIR/.credentials.json" <<EOF
{"claudeAiOauth": {"accessToken": "dummy-token", "expiresAt": $FUTURE_MS}}
EOF
CURL_ARGS_CAPTURE="$TEST_HOME/curl_args_capture.txt"
cat > "$TEST_BIN_DIR/curl" <<EOF
#!/bin/bash
printf '%s\n' "\$@" > "$CURL_ARGS_CAPTURE"
printf '%s\n200\n' '{"five_hour":{"utilization":42},"seven_day":{"utilization":10}}'
EOF
chmod +x "$TEST_BIN_DIR/curl"

PATH="$TEST_BIN_DIR:$PATH" bash -c '
    source "'"$PWD"'/home/dot_claude/scripts/limit-unlocked/executable_check-notify.sh"
    fetch_usage_status "'"$TEST_CONFIG_DIR"'"
  ' >/dev/null 2>/dev/null

if grep -Fq 'dummy-token' "$CURL_ARGS_CAPTURE"; then
  echo "❌ fetch_usage_status passed the OAuth token via curl's argument list (got: $(cat "$CURL_ARGS_CAPTURE"))"
  FAILED=1
else
  echo "✅ fetch_usage_status did not expose the OAuth token via curl's argv"
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

    # 最終チェック時刻を 31 分前に書き換える
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

echo "Testing detect_limited_sessions resumes via Usage API before reset_epoch..."
TEST_HOME=$(mktemp -d)
mkdir -p "$TEST_HOME/.claude/scripts/limit-unlocked/data"
STATE_FILE_PATH="$TEST_HOME/.claude/scripts/limit-unlocked/data/limited_sessions.txt"
touch "$STATE_FILE_PATH"
RESUME_LOG="$TEST_HOME/resume.log"

OUTPUT=$(
  HOME="$TEST_HOME" bash -c '
    source "'"$PWD"'/home/dot_claude/scripts/limit-unlocked/executable_check-notify.sh"

    STATE_FILE="'"$STATE_FILE_PATH"'"
    NEW_STATE_FILE="${STATE_FILE}.new"

    # 同一 config_dir を共有する 2 セッションがともにリミット中、という状況をスタブする
    tmux() {
      if [[ "$1" == "list-sessions" ]]; then
        printf "sess-a\nsess-b\n"
      elif [[ "$1" == "has-session" ]]; then
        return 0
      fi
    }
    resolve_claude_pid() { echo "12345"; }
    resolve_config_dir_for_pid() { echo "/fake/config-dir"; }
    resolve_jsonl_path() { echo "/dummy/${1}.jsonl"; }
    check_limit_status() { echo -e "1\t9999999999\tdummy reset text"; }
    usage_check_allowed() { return 0; }
    record_usage_checked() { :; }
    fetch_usage_status_calls=0
    fetch_usage_status() {
      fetch_usage_status_calls=$((fetch_usage_status_calls + 1))
      echo -e "42\t10"
    }
    resume_session() { echo "resumed:$1" >> "'"$RESUME_LOG"'"; }

    detect_limited_sessions

    echo "calls=$fetch_usage_status_calls"
    echo "new_state_lines=$(wc -l < "$NEW_STATE_FILE" | tr -d " ")"
  '
)

if ! grep -q '^calls=1$' <<< "$OUTPUT"; then
  echo "❌ detect_limited_sessions did not memoize fetch_usage_status per config_dir within a single run (output: $OUTPUT)"
  FAILED=1
else
  echo "✅ detect_limited_sessions memoized fetch_usage_status per config_dir within a single run"
fi

if ! grep -q '^new_state_lines=0$' <<< "$OUTPUT"; then
  echo "❌ detect_limited_sessions still recorded a Usage-API-confirmed-unlocked session in NEW_STATE_FILE"
  FAILED=1
else
  echo "✅ detect_limited_sessions excluded Usage-API-confirmed-unlocked sessions from NEW_STATE_FILE"
fi

if [ "$(wc -l < "$RESUME_LOG" 2>/dev/null | tr -d ' ')" != "2" ]; then
  echo "❌ detect_limited_sessions did not call resume_session for both unlocked sessions"
  FAILED=1
else
  echo "✅ detect_limited_sessions called resume_session for both unlocked sessions"
fi

rm -rf "$TEST_HOME"

echo "Testing detect_limited_sessions reuses the cached Usage API result even though record_usage_checked updates the throttle timestamp after the first session..."
TEST_HOME=$(mktemp -d)
mkdir -p "$TEST_HOME/.claude/scripts/limit-unlocked/data"
STATE_FILE_PATH="$TEST_HOME/.claude/scripts/limit-unlocked/data/limited_sessions.txt"
touch "$STATE_FILE_PATH"
RESUME_LOG="$TEST_HOME/resume.log"

OUTPUT=$(
  HOME="$TEST_HOME" bash -c '
    source "'"$PWD"'/home/dot_claude/scripts/limit-unlocked/executable_check-notify.sh"

    STATE_FILE="'"$STATE_FILE_PATH"'"
    NEW_STATE_FILE="${STATE_FILE}.new"

    # usage_check_allowed / record_usage_checked は Task 4 の実実装をそのまま使う
    # (スタブしない)。fetch_usage_status のみスタブし、呼び出し回数を数える。
    tmux() {
      if [[ "$1" == "list-sessions" ]]; then
        printf "sess-a\nsess-b\n"
      elif [[ "$1" == "has-session" ]]; then
        return 0
      fi
    }
    resolve_claude_pid() { echo "12345"; }
    resolve_config_dir_for_pid() { echo "/fake/config-dir"; }
    resolve_jsonl_path() { echo "/dummy/${1}.jsonl"; }
    check_limit_status() { echo -e "1\t9999999999\tdummy reset text"; }
    fetch_usage_status_calls=0
    fetch_usage_status() {
      fetch_usage_status_calls=$((fetch_usage_status_calls + 1))
      echo -e "42\t10"
    }
    resume_session() { echo "resumed:$1" >> "'"$RESUME_LOG"'"; }

    detect_limited_sessions

    echo "calls=$fetch_usage_status_calls"
    echo "new_state_lines=$(wc -l < "$NEW_STATE_FILE" | tr -d " ")"
  '
)

if ! grep -q '^calls=1$' <<< "$OUTPUT"; then
  echo "❌ detect_limited_sessions called fetch_usage_status more than once for the same config_dir with real throttling functions (output: $OUTPUT)"
  FAILED=1
else
  echo "✅ detect_limited_sessions called fetch_usage_status only once for the same config_dir with real throttling functions"
fi

if [ "$(wc -l < "$RESUME_LOG" 2>/dev/null | tr -d ' ')" != "2" ]; then
  echo "❌ detect_limited_sessions did not resume both sessions sharing a config_dir when real throttling functions are used (second session was likely skipped by the throttle instead of reusing the cached result)"
  FAILED=1
else
  echo "✅ detect_limited_sessions resumed both sessions sharing a config_dir even with real throttling functions"
fi

rm -rf "$TEST_HOME"

echo "Testing detect_limited_sessions falls back to reset_epoch tracking when Usage API check is unavailable..."
TEST_HOME=$(mktemp -d)
mkdir -p "$TEST_HOME/.claude/scripts/limit-unlocked/data"
STATE_FILE_PATH="$TEST_HOME/.claude/scripts/limit-unlocked/data/limited_sessions.txt"
touch "$STATE_FILE_PATH"

OUTPUT=$(
  HOME="$TEST_HOME" bash -c '
    source "'"$PWD"'/home/dot_claude/scripts/limit-unlocked/executable_check-notify.sh"

    STATE_FILE="'"$STATE_FILE_PATH"'"
    NEW_STATE_FILE="${STATE_FILE}.new"

    tmux() {
      if [[ "$1" == "list-sessions" ]]; then
        echo "sess-a"
      elif [[ "$1" == "display-message" ]]; then
        echo "/tmp/work"
      fi
    }
    resolve_claude_pid() { echo "12345"; }
    resolve_config_dir_for_pid() { return 1; }
    resolve_jsonl_path() { echo "/dummy/${1}.jsonl"; }
    check_limit_status() { echo -e "1\t9999999999\tdummy reset text"; }
    resume_session() { echo "resumed:$1" >> "'"$TEST_HOME/resume.log"'"; }

    detect_limited_sessions

    echo "new_state_lines=$(wc -l < "$NEW_STATE_FILE" | tr -d " ")"
  '
)

if ! grep -q '^new_state_lines=1$' <<< "$OUTPUT"; then
  echo "❌ detect_limited_sessions did not fall back to recording the session in NEW_STATE_FILE when config_dir cannot be resolved"
  FAILED=1
else
  echo "✅ detect_limited_sessions fell back to existing reset_epoch-based tracking when config_dir cannot be resolved"
fi

if [ -f "$TEST_HOME/resume.log" ]; then
  echo "❌ detect_limited_sessions should not call resume_session when Usage API confirmation is unavailable"
  FAILED=1
else
  echo "✅ detect_limited_sessions did not call resume_session when Usage API confirmation is unavailable"
fi

rm -rf "$TEST_HOME"

if [ $FAILED -eq 0 ]; then
  echo "✅ All notification script tests passed"
else
  echo "❌ Some notification script tests failed"
  exit 1
fi
