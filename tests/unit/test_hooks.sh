#!/bin/bash
# AI エージェント フックのユニットテスト

set -euo pipefail

echo "Testing AI agent hooks..."

FAILED=0

# テスト対象のフックスクリプト
HOOKS=(
  "home/dot_claude/hooks/executable_code-review-immediate-fix.sh"
  "home/dot_claude/hooks/executable_require-code-review-fixes.sh"
  "home/dot_claude/hooks/executable_require-review-thread-fixes.sh"
  "home/dot_claude/hooks/executable_git-config-guard.sh"
)

# 各フックの構文チェック
for hook in "${HOOKS[@]}"; do
  if [ ! -f "$hook" ]; then
    echo "⚠️  Hook not found: $hook"
    continue
  fi

  echo "Testing hook: $hook"

  # bash 構文チェック
  if ! bash -n "$hook"; then
    echo "❌ Syntax error in hook: $hook"
    FAILED=1
  else
    echo "✅ Syntax OK: $hook"
  fi
done

echo "Testing gh-pr-target-repo helper behavior..."
TEST_REPO_DIR=$(mktemp -d)
if ! (
  cd "$TEST_REPO_DIR" || exit 1
  git init -q
  git remote add upstream git@gitlab.com:example/not-github.git
  git remote add origin git@github.com:akubiusa/dotfiles.git
  HELPER_OUTPUT=$(bash "$OLDPWD/home/bin/executable_gh-pr-target-repo.sh")
  if [[ "$HELPER_OUTPUT" != "akubiusa/dotfiles" ]]; then
    echo "❌ gh-pr-target-repo helper did not ignore non-GitHub upstream remote"
    exit 1
  fi

  git remote set-url upstream git@github.com:book000/dotfiles.git
  HELPER_OUTPUT=$(bash "$OLDPWD/home/bin/executable_gh-pr-target-repo.sh")
  if [[ "$HELPER_OUTPUT" != "book000/dotfiles" ]]; then
    echo "❌ gh-pr-target-repo helper did not prefer GitHub upstream remote"
    exit 1
  fi
) ; then
  FAILED=1
else
  echo "✅ gh-pr-target-repo helper resolved GitHub remotes correctly"
fi
rm -rf "$TEST_REPO_DIR"

echo "Testing gh-pr-target-repo helper fallback behavior..."
TEST_REPO_DIR=$(mktemp -d)
TEST_BIN_DIR=$(mktemp -d)
if ! (
  cd "$TEST_REPO_DIR" || exit 1
  git init -q
  cat > "$TEST_BIN_DIR/gh" <<'EOF'
#!/bin/bash
if [[ "$1" == "repo" && "$2" == "view" ]]; then
  echo "fallback-owner/fallback-repo"
  exit 0
fi
exit 1
EOF
  chmod +x "$TEST_BIN_DIR/gh"

  HELPER_OUTPUT=$(PATH="$TEST_BIN_DIR:$PATH" bash "$OLDPWD/home/bin/executable_gh-pr-target-repo.sh")
  if [[ "$HELPER_OUTPUT" != "fallback-owner/fallback-repo" ]]; then
    echo "❌ gh-pr-target-repo helper did not fall back to gh repo view"
    exit 1
  fi

  if PATH="$TEST_BIN_DIR:$PATH" bash "$OLDPWD/home/bin/executable_gh-pr-target-repo.sh" --remote >/dev/null 2>&1; then
    echo "❌ gh-pr-target-repo helper returned a synthetic remote name for gh fallback"
    exit 1
  fi
) ; then
  FAILED=1
else
  echo "✅ gh-pr-target-repo helper handled gh fallback without synthetic remote names"
fi
rm -rf "$TEST_REPO_DIR" "$TEST_BIN_DIR"

echo "Testing Codex Copilot wait script notification behavior..."
TEST_HOME=$(mktemp -d)
TEST_BIN_DIR=$(mktemp -d)
TEST_LOG_DIR="$TEST_HOME/.codex/logs"
TEST_LOCK_DIR="$TEST_HOME/.codex/locks"
TEST_CAPTURE_DIR=$(mktemp -d)
mkdir -p "$TEST_HOME/bin" "$TEST_HOME/.codex/scripts/completion-notify" "$TEST_LOG_DIR" "$TEST_LOCK_DIR"

cat > "$TEST_HOME/.env" <<EOF
SOURCE_COUNT_FILE="$TEST_CAPTURE_DIR/source-count"
echo sourced >> "\$SOURCE_COUNT_FILE"
DISCORD_CODEX_MENTION_USER_ID="1234567890"
EOF

cp home/bin/executable_gh-pr-target-repo.sh "$TEST_HOME/bin/gh-pr-target-repo.sh"
chmod +x "$TEST_HOME/bin/gh-pr-target-repo.sh"

cat > "$TEST_HOME/.codex/scripts/completion-notify/send-discord-notification.sh" <<'EOF'
#!/bin/bash
cat > "${TEST_CAPTURE_DIR}/discord-payload.json"
EOF
chmod +x "$TEST_HOME/.codex/scripts/completion-notify/send-discord-notification.sh"

cat > "$TEST_BIN_DIR/gh" <<'EOF'
#!/bin/bash
if [[ "$1" == "api" && "$2" == "graphql" ]]; then
  echo "1"
  exit 0
fi
exit 1
EOF
chmod +x "$TEST_BIN_DIR/gh"

cat > "$TEST_BIN_DIR/tmux" <<'EOF'
#!/bin/bash
if [[ "$1" == "display-message" && "$2" == "-p" ]]; then
  echo "test-session"
  exit 0
fi
if [[ "$1" == "send-keys" ]]; then
  printf '%s\n' "$*" >> "${TEST_CAPTURE_DIR}/tmux.log"
  exit 0
fi
exit 1
EOF
chmod +x "$TEST_BIN_DIR/tmux"

if ! (
  TEST_CAPTURE_DIR="$TEST_CAPTURE_DIR" PATH="$TEST_BIN_DIR:$PATH" HOME="$TEST_HOME" \
    bash home/dot_agents/skills/pr-health-monitor/scripts/executable_wait-for-copilot-review.sh \
    "https://github.com/book000/dotfiles/pull/121"
); then
  echo "❌ wait-for-copilot-review.sh failed on existing review notification path"
  FAILED=1
else
  if [[ "$(wc -l < "$TEST_CAPTURE_DIR/source-count" | tr -d ' ')" != "1" ]]; then
    echo "❌ wait-for-copilot-review.sh sourced ~/.env more than once"
    FAILED=1
  else
    echo "✅ wait-for-copilot-review.sh sourced ~/.env only once"
  fi

  if ! grep -Fq '<@1234567890> Codex CLI Notification' "$TEST_CAPTURE_DIR/discord-payload.json"; then
    echo "❌ wait-for-copilot-review.sh did not include the configured mention in Discord payload"
    FAILED=1
  else
    echo "✅ wait-for-copilot-review.sh included the configured mention in Discord payload"
  fi

  if ! grep -Fq "\$handle-pr-reviews https://github.com/book000/dotfiles/pull/121" "$TEST_CAPTURE_DIR/tmux.log"; then
    echo "❌ wait-for-copilot-review.sh did not send the expected tmux command"
    FAILED=1
  else
    echo "✅ wait-for-copilot-review.sh sent the expected tmux command"
  fi
fi
rm -rf "$TEST_HOME" "$TEST_BIN_DIR" "$TEST_CAPTURE_DIR"

echo "Testing git-config-guard hook behavior..."
GIT_CONFIG_GUARD="home/dot_claude/hooks/executable_git-config-guard.sh"

run_git_config_guard() {
  local cmd="$1"
  jq -n --arg cmd "$cmd" '{"tool_input": {"command": $cmd}}' | bash "$GIT_CONFIG_GUARD"
}

# 読み取り系: 常に許可される(標準出力なし)
for cmd in \
  'git config --get user.name' \
  'git config --list' \
  'git config user.name' \
  'git status'; do
  OUTPUT=$(run_git_config_guard "$cmd")
  if [[ -n "$OUTPUT" ]]; then
    echo "❌ git-config-guard denied a command that should be allowed: $cmd"
    FAILED=1
  else
    echo "✅ git-config-guard allowed: $cmd"
  fi
done

# 書き込み系: permissionDecision: deny が出力される
for cmd in \
  'git config user.name "Foo"' \
  'git config --global user.email foo@example.com' \
  'git config --unset user.name'; do
  OUTPUT=$(run_git_config_guard "$cmd")
  DECISION=$(echo "$OUTPUT" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
  if [[ "$DECISION" != "deny" ]]; then
    echo "❌ git-config-guard did not deny a write command: $cmd"
    FAILED=1
  else
    echo "✅ git-config-guard denied: $cmd"
  fi
done

if [ $FAILED -eq 0 ]; then
  echo "✅ All hook tests passed"
else
  echo "❌ Some hook tests failed"
  exit 1
fi
