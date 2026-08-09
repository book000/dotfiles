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
  "home/dot_codex/scripts/limit-unlocked/executable_check-notify.sh"
  "home/dot_codex/scripts/completion-notify/executable_send-discord-notification.sh"
  "home/dot_codex/scripts/completion-notify/executable_notify-completion.sh"
  "home/dot_codex/scripts/completion-notify/executable_notify-permission-request.sh"
  "home/dot_codex/scripts/completion-notify/executable_notify-user-prompt-submit.sh"
  "home/dot_codex/scripts/completion-notify/executable_notify-post-tool-use.sh"
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

echo "Testing Codex completion hook returns valid Stop-hook JSON..."
TEST_HOME=$(mktemp -d)
COMPLETION_OUTPUT=$(HOME="$TEST_HOME" bash home/dot_codex/scripts/completion-notify/executable_notify-completion.sh <<'EOF'
{"session_id":"test-session","cwd":"/tmp/test","last_assistant_message":"done"}
EOF
)
if [[ "$COMPLETION_OUTPUT" != "{}" ]]; then
  echo "❌ Codex completion hook did not return an empty JSON object (got: $COMPLETION_OUTPUT)"
  FAILED=1
else
  echo "✅ Codex completion hook returned valid Stop-hook JSON"
fi
if grep -Fq 'tool_input' home/dot_codex/scripts/completion-notify/executable_notify-permission-request.sh; then
  echo "❌ Codex permission notification must not include tool input"
  FAILED=1
else
  echo "✅ Codex permission notification excludes tool input"
fi
rm -rf "$TEST_HOME"

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

# resolve_claude_pid は /proc/<pid>/comm が実際に "claude" であることを検証するため、
# 単なる sleep ではなく "claude" という名前の実行ファイルとして起動する
cat > "$TEST_BIN_DIR/claude" <<'EOF'
#!/bin/bash
sleep 60
EOF
chmod +x "$TEST_BIN_DIR/claude"

CLAUDE_CONFIG_DIR="$TEST_HOME/.claude" "$TEST_BIN_DIR/claude" &
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
# collect_descendant_pids は pane pid から再帰的に子を辿るため、pane pid (12345)
# へのクエリにのみ子として \$FAKE_CLAUDE_PID を返し、それ以外(\$FAKE_CLAUDE_PID 自身
# への再帰クエリ含む)には子なしを返して探索を打ち切る
if [[ "\$2" == "12345" ]]; then
  echo "$FAKE_CLAUDE_PID"
fi
exit 0
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

echo "Testing resolve_jsonl_path prefers a parked/background session JSONL..."
TEST_HOME=$(mktemp -d)
TEST_CONFIG_DIR="$TEST_HOME/.claude"
mkdir -p "$TEST_CONFIG_DIR/sessions" "$TEST_HOME/.claude/projects/test-project"

cat > "$TEST_CONFIG_DIR/sessions/4242.json" <<'EOF'
{"pid":4242,"sessionId":"interactive-session","parkedJobId":"job-123"}
EOF
cat > "$TEST_CONFIG_DIR/sessions/5252.json" <<'EOF'
{"pid":5252,"sessionId":"background-session","kind":"bg","jobId":"job-123"}
EOF
touch "$TEST_HOME/.claude/projects/test-project/interactive-session.jsonl"
touch "$TEST_HOME/.claude/projects/test-project/background-session.jsonl"

RESULT=$(
  HOME="$TEST_HOME" bash -c '
    source "'"$PWD"'/home/dot_claude/scripts/limit-unlocked/executable_check-notify.sh"
    resolve_jsonl_path "dummy-session" 4242 "'"$TEST_CONFIG_DIR"'"
  '
)
EXPECTED="$TEST_HOME/.claude/projects/test-project/background-session.jsonl"
if [[ "$RESULT" != "$EXPECTED" ]]; then
  echo "❌ resolve_jsonl_path did not prefer the parked/background session JSONL (got: '$RESULT', want: '$EXPECTED')"
  FAILED=1
else
  echo "✅ resolve_jsonl_path preferred the parked/background session JSONL"
fi

echo "Testing resolve_jsonl_path falls back to the interactive session when the parked session cannot be resolved..."
rm -f "$TEST_CONFIG_DIR/sessions/5252.json"
RESULT=$(
  HOME="$TEST_HOME" bash -c '
    source "'"$PWD"'/home/dot_claude/scripts/limit-unlocked/executable_check-notify.sh"
    resolve_jsonl_path "dummy-session" 4242 "'"$TEST_CONFIG_DIR"'"
  '
)
EXPECTED="$TEST_HOME/.claude/projects/test-project/interactive-session.jsonl"
if [[ "$RESULT" != "$EXPECTED" ]]; then
  echo "❌ resolve_jsonl_path did not fall back to the interactive session JSONL (got: '$RESULT', want: '$EXPECTED')"
  FAILED=1
else
  echo "✅ resolve_jsonl_path fell back to the interactive session JSONL"
fi
rm -rf "$TEST_HOME"

echo "Testing resolve_claude_pid matches a claude process invoked via a resolved absolute path, even as a grandchild of the pane pid..."
TEST_BIN_DIR=$(mktemp -d)

# 実際の cron ジョブ (CLAUDE_BIN="$(command -v claude)"; ... "$CLAUDE_BIN" ...) を模し、
# 絶対パスで実行される実体を「claude」という名前の実ファイルとして用意する。
# Linux では shebang スクリプトの comm はインタプリタ名ではなく実行された
# ファイルのベース名になるため、この方法で実際の comm=claude プロセスを再現できる
cat > "$TEST_BIN_DIR/claude" <<'EOF'
#!/bin/bash
sleep 60
EOF
chmod +x "$TEST_BIN_DIR/claude"

# pane pid 自体ではなく、その子プロセス(ラッパー)がさらに claude を起動する
# 孫プロセスの構成にして、collect_descendant_pids の再帰走査を検証する
PIDFILE=$(mktemp)
bash -c '
  "'"$TEST_BIN_DIR"'/claude" &
  echo $! > "'"$PIDFILE"'"
  wait
' &
WRAPPER_PID=$!
sleep 0.3
CLAUDE_PID=$(cat "$PIDFILE")

cat > "$TEST_BIN_DIR/tmux" <<EOF
#!/bin/bash
if [[ "\$1" == "display-message" ]]; then
  echo "$WRAPPER_PID"
  exit 0
fi
exit 1
EOF
chmod +x "$TEST_BIN_DIR/tmux"

RESULT=$(
  PATH="$TEST_BIN_DIR:$PATH" bash -c '
    source "'"$PWD"'/home/dot_claude/scripts/limit-unlocked/executable_check-notify.sh"
    resolve_claude_pid "dummy-session"
  '
)

kill "$CLAUDE_PID" "$WRAPPER_PID" 2>/dev/null || true
wait "$WRAPPER_PID" 2>/dev/null || true

if [[ "$RESULT" != "$CLAUDE_PID" ]]; then
  echo "❌ resolve_claude_pid did not find the path-invoked, grandchild claude process (got: '$RESULT', want: '$CLAUDE_PID')"
  FAILED=1
else
  echo "✅ resolve_claude_pid found the path-invoked claude process via comm, even as a grandchild of the pane pid"
fi
rm -rf "$TEST_BIN_DIR" "$PIDFILE"

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

echo "Testing Codex check-notify.sh is safely sourceable (no side effects)..."
TEST_HOME=$(mktemp -d)
if ! (
  HOME="$TEST_HOME" bash -c '
    source "'"$PWD"'/home/dot_codex/scripts/limit-unlocked/executable_check-notify.sh"
    if declare -p STATE_FILE >/dev/null 2>&1; then
      echo "STATE_FILE should not be set when sourced" >&2
      exit 1
    fi
    if ! declare -F resolve_rollout_path >/dev/null 2>&1; then
      echo "resolve_rollout_path should be defined after sourcing" >&2
      exit 1
    fi
  '
); then
  echo "❌ Codex check-notify.sh executed main logic (or failed) when sourced"
  FAILED=1
else
  echo "✅ Codex check-notify.sh only defines functions when sourced"
fi
if [ -d "$TEST_HOME/.codex/scripts/limit-unlocked/data" ]; then
  echo "❌ Codex check-notify.sh created state directory as a side effect of sourcing"
  FAILED=1
fi
rm -rf "$TEST_HOME"

echo "Testing Codex check_limit_status parses a usage_limit_exceeded task_complete with a token_count resets_at..."
TEST_HOME=$(mktemp -d)
FIXTURE_JSONL="$TEST_HOME/fixture-rollout.jsonl"
cat > "$FIXTURE_JSONL" <<'EOF'
{"timestamp":"2026-08-02T11:47:20.000Z","type":"event_msg","payload":{"type":"token_count","info":{},"rate_limits":{"limit_id":"codex","limit_name":null,"primary":{"used_percent":100.0,"window_minutes":10080,"resets_at":1786165193},"secondary":null,"credits":{"has_credits":false,"unlimited":false,"balance":"0"},"individual_limit":null,"spend_control_reached":null,"plan_type":"plus","rate_limit_reached_type":null}}}
{"timestamp":"2026-08-02T11:47:24.660Z","type":"event_msg","payload":{"type":"task_complete","turn_id":"t1","last_agent_message":null,"error":{"message":"You've hit your usage limit. Upgrade to Pro (https://chatgpt.com/explore/pro), visit https://chatgpt.com/codex/settings/usage to purchase more credits or try again at Aug 8th, 2026 1:59 PM.","codex_error_info":"usage_limit_exceeded"},"started_at":1785671243,"completed_at":1785671244,"duration_ms":1410}}
EOF

RESULT=$(
  bash -c '
    source "'"$PWD"'/home/dot_codex/scripts/limit-unlocked/executable_check-notify.sh"
    check_limit_status "'"$FIXTURE_JSONL"'"
  '
)
IFS=$'\t' read -r is_limited reset_epoch reset_text <<< "$RESULT"

if [[ "$is_limited" != "1" ]]; then
  echo "❌ check_limit_status did not detect a usage_limit_exceeded task_complete (got: '$RESULT')"
  FAILED=1
else
  echo "✅ check_limit_status detected a usage_limit_exceeded task_complete"
fi

if [[ "$reset_epoch" != "1786165193" ]]; then
  echo "❌ check_limit_status did not use the token_count rate_limits.primary.resets_at epoch (got: '$reset_epoch')"
  FAILED=1
else
  echo "✅ check_limit_status used the token_count rate_limits.primary.resets_at epoch"
fi

if [[ "$reset_text" != *"usage limit"* ]]; then
  echo "❌ check_limit_status did not carry through the error message text (got: '$reset_text')"
  FAILED=1
else
  echo "✅ check_limit_status carried through the error message text"
fi

echo "Testing Codex check_limit_status treats error:null task_complete as not limited..."
FIXTURE_JSONL_OK="$TEST_HOME/fixture-rollout-ok.jsonl"
cat > "$FIXTURE_JSONL_OK" <<'EOF'
{"timestamp":"2026-08-02T11:50:00.000Z","type":"event_msg","payload":{"type":"task_complete","turn_id":"t2","last_agent_message":"done","error":null,"started_at":1785671300,"completed_at":1785671301,"duration_ms":900}}
EOF

RESULT_OK=$(
  bash -c '
    source "'"$PWD"'/home/dot_codex/scripts/limit-unlocked/executable_check-notify.sh"
    check_limit_status "'"$FIXTURE_JSONL_OK"'"
  '
)

if [[ "$RESULT_OK" != $'0\t-\t-' ]]; then
  echo "❌ check_limit_status incorrectly reported a limited state for an error:null task_complete (got: '$RESULT_OK')"
  FAILED=1
else
  echo "✅ check_limit_status correctly reported not-limited for an error:null task_complete"
fi

echo "Testing Codex check_limit_status clears a stale usage_limit_exceeded state after a later below-cap token_count..."
FIXTURE_JSONL_STALE_LIMIT="$TEST_HOME/fixture-rollout-stale-limit.jsonl"
cat > "$FIXTURE_JSONL_STALE_LIMIT" <<'EOF'
{"timestamp":"2026-08-02T11:47:24.660Z","type":"event_msg","payload":{"type":"task_complete","turn_id":"t1","last_agent_message":null,"error":{"message":"usage limit hit","codex_error_info":"usage_limit_exceeded"},"started_at":1785671243,"completed_at":1785671244,"duration_ms":1410}}
{"timestamp":"2026-08-08T05:00:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{},"rate_limits":{"primary":{"used_percent":1.0,"window_minutes":300,"resets_at":1786168800},"secondary":null}}}
EOF

RESULT_STALE_LIMIT=$(
  bash -c '
    source "'"$PWD"'/home/dot_codex/scripts/limit-unlocked/executable_check-notify.sh"
    check_limit_status "'"$FIXTURE_JSONL_STALE_LIMIT"'"
  '
)

if [[ "$RESULT_STALE_LIMIT" != $'0\t-\t-' ]]; then
  echo "❌ check_limit_status did not clear a stale usage_limit_exceeded state (got: '$RESULT_STALE_LIMIT')"
  FAILED=1
else
  echo "✅ check_limit_status cleared a stale usage_limit_exceeded state"
fi

rm -rf "$TEST_HOME"

echo "Testing Codex resolve_rollout_path discovers the rollout jsonl via /proc fd scan and picks the newest mtime..."
TEST_HOME=$(mktemp -d)
TEST_HOME=$(readlink -f "$TEST_HOME") # /proc/<pid>/fd の readlink -f 結果と文字列比較できるよう正規化する
TEST_BIN_DIR=$(mktemp -d)
mkdir -p "$TEST_HOME/.codex/sessions/2026/08/02"

OLD_ROLLOUT="$TEST_HOME/.codex/sessions/2026/08/02/rollout-1785660000-old.jsonl"
NEW_ROLLOUT="$TEST_HOME/.codex/sessions/2026/08/02/rollout-1785671200-new.jsonl"
echo '{}' > "$OLD_ROLLOUT"
touch -d "-1 hour" "$OLD_ROLLOUT"
echo '{}' > "$NEW_ROLLOUT"

# 実際に fd を開いたまま維持するバックグラウンドプロセスを立て、fd スキャンが
# 実プロセスの /proc/<pid>/fd を正しく辿れることを end-to-end で検証する
# (同一 pid が複数の rollout fd を開いたままにする、という実運用のケースを再現する)。
# 新しい方の rollout を若い fd 番号(3)に、古い方を後の fd 番号(4)に割り当てることで、
# /proc/<pid>/fd の走査順(数字の小さい順)と mtime の新旧が逆になるようにし、
# 「単に最後に見つかったものを採用する」実装ではこのテストを通せないようにする
bash -c "exec 3<'$NEW_ROLLOUT' 4<'$OLD_ROLLOUT'; sleep 60" &
FAKE_CODEX_PID=$!
sleep 0.2

cat > "$TEST_BIN_DIR/tmux" <<EOF
#!/bin/bash
if [[ "\$1" == "display-message" ]]; then
  echo "$FAKE_CODEX_PID"
  exit 0
fi
exit 1
EOF
chmod +x "$TEST_BIN_DIR/tmux"

RESULT=$(
  PATH="$TEST_BIN_DIR:$PATH" HOME="$TEST_HOME" bash -c '
    source "'"$PWD"'/home/dot_codex/scripts/limit-unlocked/executable_check-notify.sh"
    resolve_rollout_path "dummy-session"
  '
)

kill "$FAKE_CODEX_PID" 2>/dev/null || true
wait "$FAKE_CODEX_PID" 2>/dev/null || true

if [[ "$RESULT" != "$NEW_ROLLOUT" ]]; then
  echo "❌ resolve_rollout_path did not pick the rollout jsonl with the newest mtime via /proc fd scan (got: '$RESULT', want: '$NEW_ROLLOUT')"
  FAILED=1
else
  echo "✅ resolve_rollout_path discovered the rollout jsonl via /proc fd scan and picked the newest mtime"
fi

rm -rf "$TEST_HOME" "$TEST_BIN_DIR"

echo "Testing Codex resolve_rollout_path prefers the root session rollout over a newer subagent rollout..."
TEST_HOME=$(mktemp -d)
TEST_HOME=$(readlink -f "$TEST_HOME")
TEST_BIN_DIR=$(mktemp -d)
mkdir -p "$TEST_HOME/.codex/sessions/2026/08/02"

ROOT_ROLLOUT="$TEST_HOME/.codex/sessions/2026/08/02/rollout-root.jsonl"
SUBAGENT_ROLLOUT="$TEST_HOME/.codex/sessions/2026/08/02/rollout-subagent.jsonl"
printf '%s\n' '{"type":"session_meta","payload":{"id":"root","session_id":"root","source":"cli","thread_source":"user"}}' > "$ROOT_ROLLOUT"
touch -d "-1 minute" "$ROOT_ROLLOUT"
printf '%s\n' '{"type":"session_meta","payload":{"id":"subagent","session_id":"root","source":{"subagent":{}},"thread_source":"subagent"}}' > "$SUBAGENT_ROLLOUT"

bash -c "exec 3<'$SUBAGENT_ROLLOUT' 4<'$ROOT_ROLLOUT'; sleep 60" &
FAKE_CODEX_PID=$!
sleep 0.2

cat > "$TEST_BIN_DIR/tmux" <<EOF
#!/bin/bash
if [[ "\$1" == "display-message" ]]; then
  echo "$FAKE_CODEX_PID"
  exit 0
fi
exit 1
EOF
chmod +x "$TEST_BIN_DIR/tmux"

RESULT_ROOT=$(
  PATH="$TEST_BIN_DIR:$PATH" HOME="$TEST_HOME" bash -c '
    source "'"$PWD"'/home/dot_codex/scripts/limit-unlocked/executable_check-notify.sh"
    resolve_rollout_path "dummy-session"
  '
)

kill "$FAKE_CODEX_PID" 2>/dev/null || true
wait "$FAKE_CODEX_PID" 2>/dev/null || true

if [[ "$RESULT_ROOT" != "$ROOT_ROLLOUT" ]]; then
  echo "❌ resolve_rollout_path preferred a newer subagent rollout over the root session rollout (got: '$RESULT_ROOT', want: '$ROOT_ROLLOUT')"
  FAILED=1
else
  echo "✅ resolve_rollout_path preferred the root session rollout over a newer subagent rollout"
fi

rm -rf "$TEST_HOME" "$TEST_BIN_DIR"

echo "Testing Codex check_limit_status reports status=2 (undetermined) when jq fails to parse the scanned window..."
TEST_HOME=$(mktemp -d)
FIXTURE_JSONL_BROKEN="$TEST_HOME/fixture-rollout-broken.jsonl"
printf '{not valid json\n' > "$FIXTURE_JSONL_BROKEN"

RESULT_BROKEN=$(
  bash -c '
    source "'"$PWD"'/home/dot_codex/scripts/limit-unlocked/executable_check-notify.sh"
    check_limit_status "'"$FIXTURE_JSONL_BROKEN"'"
  '
)

if [[ "$RESULT_BROKEN" != $'2\t-\t-' ]]; then
  echo "❌ check_limit_status did not report status=2 for an unparseable jsonl window (got: '$RESULT_BROKEN')"
  FAILED=1
else
  echo "✅ check_limit_status reported status=2 (undetermined) instead of silently treating a parse failure as not-limited"
fi
rm -rf "$TEST_HOME"

echo "Testing Codex check_limit_status prefers the rate-limit window actually at 100% used_percent over an unconditional primary preference..."
TEST_HOME=$(mktemp -d)
FIXTURE_JSONL_SECONDARY="$TEST_HOME/fixture-rollout-secondary.jsonl"
cat > "$FIXTURE_JSONL_SECONDARY" <<'EOF'
{"timestamp":"2026-08-02T11:47:20.000Z","type":"event_msg","payload":{"type":"token_count","info":{},"rate_limits":{"limit_id":"codex","limit_name":null,"primary":{"used_percent":40.0,"window_minutes":300,"resets_at":1111111111},"secondary":{"used_percent":100.0,"window_minutes":10080,"resets_at":2222222222},"credits":{"has_credits":false,"unlimited":false,"balance":"0"},"individual_limit":null,"spend_control_reached":null,"plan_type":"plus","rate_limit_reached_type":null}}}
{"timestamp":"2026-08-02T11:47:24.660Z","type":"event_msg","payload":{"type":"task_complete","turn_id":"t1","last_agent_message":null,"error":{"message":"usage limit hit","codex_error_info":"usage_limit_exceeded"},"started_at":1785671243,"completed_at":1785671244,"duration_ms":1410}}
EOF

RESULT_SECONDARY=$(
  bash -c '
    source "'"$PWD"'/home/dot_codex/scripts/limit-unlocked/executable_check-notify.sh"
    check_limit_status "'"$FIXTURE_JSONL_SECONDARY"'"
  '
)
IFS=$'\t' read -r _ reset_epoch_secondary _ <<< "$RESULT_SECONDARY"

if [[ "$reset_epoch_secondary" != "2222222222" ]]; then
  echo "❌ check_limit_status did not prefer the secondary window's resets_at even though only secondary is at 100% used_percent (got: '$reset_epoch_secondary')"
  FAILED=1
else
  echo "✅ check_limit_status preferred the at-cap secondary window's resets_at over an unconditional primary preference"
fi
rm -rf "$TEST_HOME"

echo "Testing Codex goal_resume_required fails safely when the rollout window contains malformed JSON..."
TEST_HOME=$(mktemp -d)
FIXTURE_JSONL_GOAL_PARSE_ERROR="$TEST_HOME/fixture-rollout-goal-parse-error.jsonl"
cat > "$FIXTURE_JSONL_GOAL_PARSE_ERROR" <<'EOF'
{"timestamp":"2026-08-08T05:00:00.000Z","type":"event_msg","payload":{"type":"thread_goal_updated","threadId":"thread-1","goal":{"threadId":"thread-1","objective":"finish the task","status":"usageLimited","tokensUsed":100,"timeUsedSeconds":60,"createdAt":1,"updatedAt":2}}}
{not-json
EOF

RESULT_GOAL_PARSE_ERROR=$(
  HOME="$TEST_HOME" bash -c '
    source "'"$PWD"'/home/dot_codex/scripts/limit-unlocked/executable_check-notify.sh"
    if goal_resume_required "'"$FIXTURE_JSONL_GOAL_PARSE_ERROR"'"; then
      printf "%s\n" required
    else
      printf "%s\n" not-required
    fi
  '
)
if [[ "$RESULT_GOAL_PARSE_ERROR" != "not-required" ]]; then
  echo "❌ goal_resume_required treated a malformed rollout as safely resumable (got: '$RESULT_GOAL_PARSE_ERROR')"
  FAILED=1
else
  echo "✅ goal_resume_required failed safely on malformed rollout JSON"
fi
rm -rf "$TEST_HOME"

echo "Testing Codex resume_session keeps the generic resume message for a non-goal session..."
TEST_HOME=$(mktemp -d)
FIXTURE_JSONL_NON_GOAL="$TEST_HOME/fixture-rollout-non-goal.jsonl"
cat > "$FIXTURE_JSONL_NON_GOAL" <<'EOF'
{"timestamp":"2026-08-08T05:00:00.000Z","type":"event_msg","payload":{"type":"task_complete","turn_id":"t1","last_agent_message":null,"error":{"message":"usage limit hit","codex_error_info":"usage_limit_exceeded"},"started_at":1,"completed_at":2,"duration_ms":1000}}
EOF

RESULT_NON_GOAL_RESUME=$(
  HOME="$TEST_HOME" bash -c '
    source "'"$PWD"'/home/dot_codex/scripts/limit-unlocked/executable_check-notify.sh"
    resolve_rollout_path() { printf "%s\n" "'"$FIXTURE_JSONL_NON_GOAL"'"; }
    sleep() { :; }
    tmux() { printf "%s\n" "$*"; }
    resume_session "sess-1"
  '
)
EXPECTED_NON_GOAL_RESUME="send-keys -t sess-1: <system-reminder>Codex's rate limit has been lifted. Continue the task you were working on before the interruption.</system-reminder>"
EXPECTED_NON_GOAL_RESUME="${EXPECTED_NON_GOAL_RESUME}"$'\n'"send-keys -t sess-1: Enter"
if [[ "$RESULT_NON_GOAL_RESUME" != "$EXPECTED_NON_GOAL_RESUME" ]]; then
  echo "❌ resume_session changed the non-goal resume input unexpectedly (got: '$RESULT_NON_GOAL_RESUME')"
  FAILED=1
else
  echo "✅ resume_session kept the generic resume message for a non-goal session"
fi
rm -rf "$TEST_HOME"

echo "Testing Codex resume_session sends /goal resume when the current goal is usage limited..."
TEST_HOME=$(mktemp -d)
FIXTURE_JSONL_GOAL_LIMITED="$TEST_HOME/fixture-rollout-goal-limited.jsonl"
cat > "$FIXTURE_JSONL_GOAL_LIMITED" <<'EOF'
{"timestamp":"2026-08-08T05:00:00.000Z","type":"event_msg","payload":{"type":"thread_goal_updated","threadId":"thread-1","goal":{"threadId":"thread-1","objective":"finish the task","status":"usageLimited","tokensUsed":100,"timeUsedSeconds":60,"createdAt":1,"updatedAt":2}}}
EOF

RESULT_GOAL_RESUME=$(
  HOME="$TEST_HOME" bash -c '
    source "'"$PWD"'/home/dot_codex/scripts/limit-unlocked/executable_check-notify.sh"
    resolve_rollout_path() { printf "%s\n" "'"$FIXTURE_JSONL_GOAL_LIMITED"'"; }
    sleep() { :; }
    tmux() { printf "%s\n" "$*"; }
    resume_session "sess-1"
  '
)
EXPECTED_GOAL_RESUME=$'send-keys -t sess-1: /goal resume\nsend-keys -t sess-1: Enter'
if [[ "$RESULT_GOAL_RESUME" != "$EXPECTED_GOAL_RESUME" ]]; then
  echo "❌ resume_session did not use /goal resume for a usage-limited goal (got: '$RESULT_GOAL_RESUME')"
  FAILED=1
else
  echo "✅ resume_session used /goal resume for a usage-limited goal"
fi
rm -rf "$TEST_HOME"

echo "Testing Codex already_resumed_for / record_resumed_for dedup resume_session for the same reset_epoch..."
TEST_HOME=$(mktemp -d)
RESULT_RESUME_DEDUP=$(
  HOME="$TEST_HOME" bash -c '
    source "'"$PWD"'/home/dot_codex/scripts/limit-unlocked/executable_check-notify.sh"
    already_resumed_for "sess-1" "1700000000" && echo "unexpected-already-resumed"
    record_resumed_for "sess-1" "1700000000"
    already_resumed_for "sess-1" "1700000000" && echo "resumed-for-same-epoch"
    already_resumed_for "sess-1" "1700000001" || echo "not-resumed-for-different-epoch"
  '
)
if [[ "$RESULT_RESUME_DEDUP" != $'resumed-for-same-epoch\nnot-resumed-for-different-epoch' ]]; then
  echo "❌ already_resumed_for/record_resumed_for did not correctly dedup resume attempts per reset_epoch (got: '$RESULT_RESUME_DEDUP')"
  FAILED=1
else
  echo "✅ already_resumed_for/record_resumed_for correctly dedup resume attempts keyed by reset_epoch"
fi
rm -rf "$TEST_HOME"

echo "Testing Codex already_notified_for / record_notified_for dedup Discord notifications for the same reset_epoch..."
TEST_HOME=$(mktemp -d)
RESULT_NOTIFY_DEDUP=$(
  HOME="$TEST_HOME" bash -c '
    source "'"$PWD"'/home/dot_codex/scripts/limit-unlocked/executable_check-notify.sh"
    already_notified_for "sess-1" "1700000000" && echo "unexpected-already-notified"
    record_notified_for "sess-1" "1700000000"
    already_notified_for "sess-1" "1700000000" && echo "notified-for-same-epoch"
    already_notified_for "sess-1" "1700000001" || echo "not-notified-for-different-epoch"
  '
)
if [[ "$RESULT_NOTIFY_DEDUP" != $'notified-for-same-epoch\nnot-notified-for-different-epoch' ]]; then
  echo "❌ already_notified_for/record_notified_for did not correctly dedup notifications per reset_epoch (got: '$RESULT_NOTIFY_DEDUP')"
  FAILED=1
else
  echo "✅ already_notified_for/record_notified_for correctly dedup notifications keyed by reset_epoch"
fi
rm -rf "$TEST_HOME"

echo "Testing Codex send_discord returns failure on a non-2xx HTTP response instead of silently swallowing it..."
TEST_BIN_DIR=$(mktemp -d)
cat > "$TEST_BIN_DIR/curl" <<'EOF'
#!/bin/bash
echo -n "500"
EOF
chmod +x "$TEST_BIN_DIR/curl"

if PATH="$TEST_BIN_DIR:$PATH" bash -c '
  source "'"$PWD"'/home/dot_codex/scripts/limit-unlocked/executable_check-notify.sh"
  DISCORD_WEBHOOK_URL="https://example.invalid/webhook"
  send_discord "title" "description" 123
' 2>/dev/null; then
  echo "❌ send_discord did not report failure for a non-2xx Discord HTTP response"
  FAILED=1
else
  echo "✅ send_discord reported failure for a non-2xx Discord HTTP response"
fi
rm -rf "$TEST_BIN_DIR"

echo "Testing Codex carry_forward_previous_entry drops a session after enough consecutive resolve failures instead of preserving it forever..."
TEST_HOME=$(mktemp -d)
STATE_FILE_STALE="$TEST_HOME/limited_sessions.txt"
NEW_STATE_FILE_STALE="${STATE_FILE_STALE}.new"
printf 'stale-sess\t/tmp/proj\t1111111111\tsome text\t1\n' > "$STATE_FILE_STALE"
: > "$NEW_STATE_FILE_STALE"

RESULT_STALE=$(
  HOME="$TEST_HOME" STATE_FILE="$STATE_FILE_STALE" NEW_STATE_FILE="$NEW_STATE_FILE_STALE" bash -c '
    source "'"$PWD"'/home/dot_codex/scripts/limit-unlocked/executable_check-notify.sh"
    for _ in $(seq 1 12); do
      : > "$NEW_STATE_FILE"
      carry_forward_previous_entry "stale-sess"
    done
    cat "$NEW_STATE_FILE"
  '
)

if [[ -n "$RESULT_STALE" ]]; then
  echo "❌ carry_forward_previous_entry kept carrying a session forward past the consecutive-failure threshold (got: '$RESULT_STALE')"
  FAILED=1
else
  echo "✅ carry_forward_previous_entry stopped carrying a session forward after the consecutive-failure threshold was reached"
fi
rm -rf "$TEST_HOME"

echo "Testing Codex detect_limited_sessions preserves STATE_FILE when tmux list-sessions itself fails..."
TEST_HOME=$(mktemp -d)
TEST_BIN_DIR=$(mktemp -d)
STATE_FILE_ENUM_FAIL="$TEST_HOME/limited_sessions.txt"
NEW_STATE_FILE_ENUM_FAIL="${STATE_FILE_ENUM_FAIL}.new"
printf 'tracked-sess\t/tmp/proj\t1111111111\tsome text\t1\n' > "$STATE_FILE_ENUM_FAIL"

cat > "$TEST_BIN_DIR/tmux" <<'EOF'
#!/bin/bash
exit 1
EOF
chmod +x "$TEST_BIN_DIR/tmux"

if PATH="$TEST_BIN_DIR:$PATH" HOME="$TEST_HOME" STATE_FILE="$STATE_FILE_ENUM_FAIL" NEW_STATE_FILE="$NEW_STATE_FILE_ENUM_FAIL" bash -c '
  source "'"$PWD"'/home/dot_codex/scripts/limit-unlocked/executable_check-notify.sh"
  detect_limited_sessions
'; then
  echo "❌ detect_limited_sessions did not report failure when tmux list-sessions failed with existing tracked state"
  FAILED=1
else
  echo "✅ detect_limited_sessions reported failure instead of silently wiping tracked state when tmux list-sessions failed"
fi
rm -rf "$TEST_HOME" "$TEST_BIN_DIR"

if [ $FAILED -eq 0 ]; then
  echo "✅ All notification script tests passed"
else
  echo "❌ Some notification script tests failed"
  exit 1
fi
