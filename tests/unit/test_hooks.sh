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

echo "Testing pre-commit hook (gitleaks secret scan)..."
PRECOMMIT_HOOK="home/dot_config/git/hooks/executable_pre-commit"

if [ ! -f "$PRECOMMIT_HOOK" ]; then
  echo "❌ pre-commit hook not found: $PRECOMMIT_HOOK"
  FAILED=1
else
  if ! bash -n "$PRECOMMIT_HOOK"; then
    echo "❌ Syntax error in pre-commit hook"
    FAILED=1
  else
    echo "✅ Syntax OK: $PRECOMMIT_HOOK"
  fi

  # シナリオ 1: gitleaks が PATH に無い場合は fail-open (exit 0 かつ警告) となること
  TEST_REPO_DIR=$(mktemp -d)
  TEST_BIN_DIR=$(mktemp -d)
  if ! (
    cd "$TEST_REPO_DIR" || exit 1
    git init -q
    HOOK_OUTPUT=$(PATH="$TEST_BIN_DIR" "$(command -v bash)" "$OLDPWD/$PRECOMMIT_HOOK" 2>&1)
    HOOK_EXIT=$?
    if [[ $HOOK_EXIT -ne 0 ]]; then
      echo "❌ pre-commit hook did not fail-open when gitleaks is missing (exit $HOOK_EXIT)"
      exit 1
    fi
    if ! echo "$HOOK_OUTPUT" | grep -qi "gitleaks not found"; then
      echo "❌ pre-commit hook did not warn about missing gitleaks"
      exit 1
    fi
  ); then
    FAILED=1
  else
    echo "✅ pre-commit hook fails open when gitleaks is missing"
  fi
  rm -rf "$TEST_REPO_DIR" "$TEST_BIN_DIR"

  # シナリオ 2: gitleaks がシークレットを検知した場合は exit 1 でブロックすること
  TEST_REPO_DIR=$(mktemp -d)
  TEST_BIN_DIR=$(mktemp -d)
  cat > "$TEST_BIN_DIR/gitleaks" << 'EOF'
#!/bin/bash
echo "leaks found" >&2
exit 1
EOF
  chmod +x "$TEST_BIN_DIR/gitleaks"
  if ! (
    cd "$TEST_REPO_DIR" || exit 1
    git init -q
    if PATH="$TEST_BIN_DIR:$PATH" bash "$OLDPWD/$PRECOMMIT_HOOK" > /dev/null 2>&1; then
      echo "❌ pre-commit hook did not block commit when gitleaks detected a secret"
      exit 1
    fi
  ); then
    FAILED=1
  else
    echo "✅ pre-commit hook blocks commit when gitleaks detects a secret"
  fi
  rm -rf "$TEST_REPO_DIR" "$TEST_BIN_DIR"

  # シナリオ 3: リポジトリ側に .gitleaks.toml が無い場合はグローバル設定にフォールバックすること
  TEST_REPO_DIR=$(mktemp -d)
  TEST_BIN_DIR=$(mktemp -d)
  TEST_HOME=$(mktemp -d)
  TEST_ARGS_LOG=$(mktemp)
  cat > "$TEST_BIN_DIR/gitleaks" << EOF
#!/bin/bash
echo "\$*" > "$TEST_ARGS_LOG"
exit 0
EOF
  chmod +x "$TEST_BIN_DIR/gitleaks"
  echo "title = \"test\"" > "$TEST_HOME/.gitleaks.toml"
  if ! (
    cd "$TEST_REPO_DIR" || exit 1
    git init -q
    HOME="$TEST_HOME" PATH="$TEST_BIN_DIR:$PATH" bash "$OLDPWD/$PRECOMMIT_HOOK" > /dev/null 2>&1
    if ! grep -q -- "--config $TEST_HOME/.gitleaks.toml" "$TEST_ARGS_LOG"; then
      echo "❌ pre-commit hook did not fall back to the global gitleaks config"
      exit 1
    fi
    if ! grep -q -- "protect --staged --redact -v" "$TEST_ARGS_LOG"; then
      echo "❌ pre-commit hook did not pass protect --staged --redact -v to gitleaks"
      exit 1
    fi
  ); then
    FAILED=1
  else
    echo "✅ pre-commit hook falls back to the global gitleaks config when the repo has none"
  fi
  rm -rf "$TEST_REPO_DIR" "$TEST_BIN_DIR" "$TEST_HOME" "$TEST_ARGS_LOG"

  # シナリオ 4: リポジトリ側に .gitleaks.toml がある場合は --config を渡さず自動検出に任せること
  TEST_REPO_DIR=$(mktemp -d)
  TEST_BIN_DIR=$(mktemp -d)
  TEST_ARGS_LOG=$(mktemp)
  cat > "$TEST_BIN_DIR/gitleaks" << EOF
#!/bin/bash
echo "\$*" > "$TEST_ARGS_LOG"
exit 0
EOF
  chmod +x "$TEST_BIN_DIR/gitleaks"
  if ! (
    cd "$TEST_REPO_DIR" || exit 1
    git init -q
    echo 'title = "repo-local"' > .gitleaks.toml
    PATH="$TEST_BIN_DIR:$PATH" bash "$OLDPWD/$PRECOMMIT_HOOK" > /dev/null 2>&1
    if grep -q -- "--config" "$TEST_ARGS_LOG"; then
      echo "❌ pre-commit hook overrode the repo's own .gitleaks.toml"
      exit 1
    fi
    if ! grep -q -- "protect --staged --redact -v" "$TEST_ARGS_LOG"; then
      echo "❌ pre-commit hook did not pass protect --staged --redact -v to gitleaks"
      exit 1
    fi
  ); then
    FAILED=1
  else
    echo "✅ pre-commit hook defers to the repo's own .gitleaks.toml when present"
  fi
  rm -rf "$TEST_REPO_DIR" "$TEST_BIN_DIR" "$TEST_ARGS_LOG"

  # シナリオ 5: グローバルフォールバック設定 (home/dot_gitleaks.toml) が構文的に有効な TOML であること
  # (gitleaks は設定エラーとシークレット検知の両方で同じ終了コードを返すため、構文エラーが
  # 混入すると全リポジトリでコミットが無差別にブロックされる。real gitleaks は使わずに TOML
  # 構文のみを検証する)
  GITLEAKS_CONFIG="home/dot_gitleaks.toml"
  if ! python3 -c "import tomllib, sys; tomllib.load(open(sys.argv[1], 'rb'))" "$GITLEAKS_CONFIG"; then
    echo "❌ $GITLEAKS_CONFIG is not valid TOML"
    FAILED=1
  else
    echo "✅ $GITLEAKS_CONFIG is valid TOML"
  fi
fi

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
# (回避策として、読み取りコマンドとの連結や、書き込みコマンドへの
# 読み取り系オプション付与によるすり抜けを試みるケースも含む)
for cmd in \
  'git config user.name "Foo"' \
  'git config --global user.email foo@example.com' \
  'git config --unset user.name' \
  'git config --list && git config user.name attacker' \
  'git config user.name attacker --get x' \
  'git config user.name attacker && echo git config'; do
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
