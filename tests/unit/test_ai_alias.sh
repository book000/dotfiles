#!/bin/bash
# AI CLI alias/functions のユニットテスト
set -euo pipefail

SCRIPT="$(pwd)/home/dot_bashrc.d/executable_90-ai-alias.sh"
set +e
# shellcheck source=/dev/null
source "$SCRIPT"
SOURCE_RC=$?
set -e
[[ $SOURCE_RC -eq 0 ]] || { echo "❌ failed to source AI alias definitions"; exit 1; }

declare -F _claude_warn_remote_settings >/dev/null || {
  echo "❌ _claude_warn_remote_settings is not defined"
  exit 1
}

TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT
SLEEP_LOG="$TEST_ROOT/sleep.log"

sleep() {
  printf '%s\n' "$1" >> "$SLEEP_LOG"
  if [[ -n "${EVENT_LOG:-}" ]]; then
    printf 'sleep:%s\n' "$1" >> "$EVENT_LOG"
  fi
}

run_check() {
  local env_dir="$1"
  local output_file="$2"
  : > "$SLEEP_LOG"
  CLAUDE_ENV_FILE="$env_dir" _claude_warn_remote_settings 2> "$output_file"
}

echo "Testing empty remote-settings.json does not warn..."
EMPTY_DIR="$TEST_ROOT/empty"
mkdir -p "$EMPTY_DIR"
printf '{ }\n' > "$EMPTY_DIR/remote-settings.json"
run_check "$EMPTY_DIR" "$TEST_ROOT/empty.err"
[[ ! -s "$SLEEP_LOG" ]] || { echo "❌ empty settings triggered sleep"; exit 1; }
[[ ! -s "$TEST_ROOT/empty.err" ]] || { echo "❌ empty settings triggered warning"; exit 1; }
echo "✅ empty settings test passed"

echo "Testing non-empty remote-settings.json warns and sleeps 10 seconds..."
NONEMPTY_DIR="$TEST_ROOT/nonempty"
mkdir -p "$NONEMPTY_DIR"
printf '{"model":"opus"}\n' > "$NONEMPTY_DIR/remote-settings.json"
run_check "$NONEMPTY_DIR" "$TEST_ROOT/nonempty.err"
[[ "$(cat "$SLEEP_LOG")" == "10" ]] || { echo "❌ non-empty settings did not sleep 10 seconds"; exit 1; }
grep -Fq 'remote-settings.json' "$TEST_ROOT/nonempty.err" || { echo "❌ warning does not identify remote-settings.json"; exit 1; }
grep -Fq '10' "$TEST_ROOT/nonempty.err" || { echo "❌ warning does not mention 10 seconds"; exit 1; }
echo "✅ non-empty settings test passed"

echo "Testing invalid JSON warns and sleeps 10 seconds..."
INVALID_DIR="$TEST_ROOT/invalid"
mkdir -p "$INVALID_DIR"
printf 'not-json\n' > "$INVALID_DIR/remote-settings.json"
run_check "$INVALID_DIR" "$TEST_ROOT/invalid.err"
[[ "$(cat "$SLEEP_LOG")" == "10" ]] || { echo "❌ invalid JSON did not sleep 10 seconds"; exit 1; }
echo "✅ invalid JSON test passed"

echo "Testing missing remote-settings.json does not warn..."
MISSING_DIR="$TEST_ROOT/missing"
mkdir -p "$MISSING_DIR"
run_check "$MISSING_DIR" "$TEST_ROOT/missing.err"
[[ ! -s "$SLEEP_LOG" ]] || { echo "❌ missing settings triggered sleep"; exit 1; }
[[ ! -s "$TEST_ROOT/missing.err" ]] || { echo "❌ missing settings triggered warning"; exit 1; }
echo "✅ missing settings test passed"

echo "Testing unset CLAUDE_ENV_FILE does not warn..."
: > "$SLEEP_LOG"
unset CLAUDE_ENV_FILE
_claude_warn_remote_settings 2> "$TEST_ROOT/unset.err"
[[ ! -s "$SLEEP_LOG" ]] || { echo "❌ unset CLAUDE_ENV_FILE triggered sleep"; exit 1; }
[[ ! -s "$TEST_ROOT/unset.err" ]] || { echo "❌ unset CLAUDE_ENV_FILE triggered warning"; exit 1; }
echo "✅ unset CLAUDE_ENV_FILE test passed"

echo "Testing claude wrapper checks settings before launching Claude..."
FAKE_HOME="$TEST_ROOT/home"
FAKE_BIN="$TEST_ROOT/bin"
WRAPPER_ENV="$TEST_ROOT/wrapper-env"
EVENT_LOG="$TEST_ROOT/events.log"
mkdir -p "$FAKE_HOME/.local/share/chezmoi" "$FAKE_BIN" "$WRAPPER_ENV"
printf '#!/bin/bash\nexit 0\n' > "$FAKE_HOME/.local/share/chezmoi/update.sh"
cat > "$FAKE_BIN/claude" <<'EOF'
#!/bin/bash
printf 'claude:%s\n' "$*" >> "$EVENT_LOG"
EOF
chmod +x "$FAKE_HOME/.local/share/chezmoi/update.sh" "$FAKE_BIN/claude"
printf '{"model":"opus"}\n' > "$WRAPPER_ENV/remote-settings.json"
: > "$SLEEP_LOG"
: > "$EVENT_LOG"
export EVENT_LOG
HOME="$FAKE_HOME" PATH="$FAKE_BIN:/usr/bin:/bin" CLAUDE_ENV_FILE="$WRAPPER_ENV" claude --version 2> "$TEST_ROOT/wrapper.err"
[[ "$(cat "$SLEEP_LOG")" == "10" ]] || { echo "❌ claude wrapper did not sleep 10 seconds"; exit 1; }
[[ "$(sed -n '1p' "$EVENT_LOG")" == "sleep:10" ]] || { echo "❌ warning delay did not occur before Claude launch"; exit 1; }
grep -Fq 'claude:--permission-mode auto --version' "$EVENT_LOG" || { echo "❌ wrapped Claude command was not launched"; exit 1; }
echo "✅ claude wrapper warning order test passed"


echo "Testing codex wrapper auto-connects only TUI launches to running app-server..."
declare -F codex >/dev/null || { echo "❌ codex wrapper function is not defined"; exit 1; }
CODEX_HOME="$TEST_ROOT/codex-home"
CODEX_BIN="$TEST_ROOT/codex-bin"
CODEX_LOG="$TEST_ROOT/codex-events.log"
mkdir -p "$CODEX_HOME/.local/share/chezmoi" "$CODEX_BIN"
printf '#!/bin/bash\nexit 0\n' > "$CODEX_HOME/.local/share/chezmoi/update.sh"
cat > "$CODEX_BIN/codex" <<'EOF'
#!/bin/bash
printf 'codex:%s\n' "$*" >> "$CODEX_LOG"
if [[ "$*" == "app-server daemon version" ]]; then
  if [[ "${FAKE_CODEX_DAEMON_STATUS:-running}" == "running" ]]; then
    printf '{"status":"running"}\n'
  else
    printf '{"status":"stopped"}\n'
  fi
fi
EOF
chmod +x "$CODEX_HOME/.local/share/chezmoi/update.sh" "$CODEX_BIN/codex"
export CODEX_LOG

: > "$CODEX_LOG"
HOME="$CODEX_HOME" PATH="$CODEX_BIN:/usr/bin:/bin" FAKE_CODEX_DAEMON_STATUS=running codex resume session-123
[[ "$(tail -n 1 "$CODEX_LOG")" == "codex:--remote unix:// --yolo resume session-123" ]] || {
  echo "❌ running daemon did not route Codex TUI through unix remote"
  cat "$CODEX_LOG"
  exit 1
}

: > "$CODEX_LOG"
HOME="$CODEX_HOME" PATH="$CODEX_BIN:/usr/bin:/bin" FAKE_CODEX_DAEMON_STATUS=stopped codex resume session-123
[[ "$(tail -n 1 "$CODEX_LOG")" == "codex:--yolo resume session-123" ]] || {
  echo "❌ stopped daemon did not fall back to local Codex TUI"
  cat "$CODEX_LOG"
  exit 1
}

: > "$CODEX_LOG"
HOME="$CODEX_HOME" PATH="$CODEX_BIN:/usr/bin:/bin" FAKE_CODEX_DAEMON_STATUS=running codex app-server daemon version >/dev/null
[[ "$(tail -n 1 "$CODEX_LOG")" == "codex:--yolo app-server daemon version" ]] || {
  echo "❌ app-server management command was unexpectedly remote-routed"
  cat "$CODEX_LOG"
  exit 1
}
! grep -Fq -- '--remote' "$CODEX_LOG" || {
  echo "❌ management command log contains --remote"
  cat "$CODEX_LOG"
  exit 1
}
echo "✅ codex wrapper routing test passed"
