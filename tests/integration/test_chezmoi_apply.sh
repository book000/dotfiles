#!/bin/bash
# chezmoi apply の統合テスト

set -euo pipefail

echo "Testing chezmoi apply..."

# テスト用の HOME ディレクトリを作成
TEST_HOME=$(mktemp -d)
export HOME=$TEST_HOME
export XDG_CONFIG_HOME="$TEST_HOME/.config"

# テスト終了時にクリーンアップ
cleanup() {
  rm -rf "$TEST_HOME"
}
trap cleanup EXIT

# chezmoi バイナリの場所を確認
CHEZMOI_BIN="./bin/chezmoi"
if [ ! -x "$CHEZMOI_BIN" ]; then
  # リポジトリに含まれていない場合は chezmoi をインストール
  echo "chezmoi not found in ./bin/, installing..."
  curl -sfL --retry 5 --retry-delay 5 https://git.io/chezmoi | sh -s -- -b "$TEST_HOME/bin"
  CHEZMOI_BIN="$TEST_HOME/bin/chezmoi"
fi

# chezmoi を初期化
# .chezmoiroot ファイルが存在するため、リポジトリルート全体をソースとして指定
SOURCE_DIR="$(pwd)"
"$CHEZMOI_BIN" init --source="$SOURCE_DIR"

# 旧 managed file と意図的な unmanaged file を用意し、削除追従を検証する。
STALE_TARGETS=(
  "$HOME/.bashrc.d/91-tmux-ipc.sh"
  "$HOME/.claude/RTK.md"
  "$HOME/.claude/commands/issue-pr.md"
  "$HOME/.codex/hooks/tmux-ipc-check.sh"
  "$HOME/bin/tmux-ipc-send.sh"
  "$HOME/.claude/rules/workflow.md"
  "$HOME/.claude/rules/workflow-sub-agents.md"
  "$HOME/.claude/rules/design-workflow.md"
  "$HOME/.claude/rules/issue-comment-docs.md"
  "$HOME/.claude/skills/deep-review/reviewers/g-performance.md"
  "$HOME/.claude/skills/deep-review/reviewers/h-error-handling.md"
  "$HOME/.claude/skills/deep-review/reviewers/i-type-design-tests.md"
  "$HOME/.agents/skills/deep-review/reviewers/g-performance.md"
  "$HOME/.agents/skills/deep-review/reviewers/h-error-handling.md"
  "$HOME/.agents/skills/deep-review/reviewers/i-type-design-tests.md"
  "$HOME/.claude/skills/handle-pr-reviews/SKILL.md"
  "$HOME/.claude/skills/wait-for-copilot-review/SKILL.md"
  "$HOME/.claude/skills/wait-for-pr-close/SKILL.md"
)
for target in "${STALE_TARGETS[@]}"; do
  mkdir -p "$(dirname "$target")"
  printf 'stale\n' > "$target"
done
LOCAL_RUNTIME_FILE="$HOME/.claude/local-runtime-state.keep"
printf 'keep\n' > "$LOCAL_RUNTIME_FILE"

# Claude Code のグローバル runtime state を保持しつつ、管理対象キーだけ更新されることを検証する。
CLAUDE_GLOBAL_CONFIG="$HOME/.claude.json"
cat > "$CLAUDE_GLOBAL_CONFIG" <<'JSON'
{
  "oauthAccount": {"accountUuid": "keep-me"},
  "projects": {"/tmp/example": {"hasTrustDialogAccepted": true}},
  "diffSidebarOpen": true
}
JSON

# chezmoi apply を実行 (dry-run)
if ! "$CHEZMOI_BIN" apply --dry-run --source="$SOURCE_DIR"; then
  echo "❌ chezmoi apply dry-run failed"
  exit 1
fi

echo "✅ chezmoi apply dry-run passed"

# 実際に apply
if ! "$CHEZMOI_BIN" apply --source="$SOURCE_DIR"; then
  echo "❌ chezmoi apply failed"
  exit 1
fi

echo "✅ chezmoi apply passed"

SYSTEMD_USER_DIR="$HOME/.config/systemd/user"
if ! grep -Fq '/usr/bin/mkr wrap -n chezmoi-update -d -a -w -- %h/.local/share/chezmoi/update.sh --force' "$SYSTEMD_USER_DIR/chezmoi-update.service"; then
  echo "❌ chezmoi-update.service was not deployed with the scheduled updater command"
  exit 1
fi
if ! grep -Fq 'Persistent=true' "$SYSTEMD_USER_DIR/chezmoi-update.timer"; then
  echo "❌ chezmoi-update.timer was not deployed as a persistent timer"
  exit 1
fi
if [ ! -L "$SYSTEMD_USER_DIR/timers.target.wants/chezmoi-update.timer" ] \
  || [ "$(readlink "$SYSTEMD_USER_DIR/timers.target.wants/chezmoi-update.timer")" != "../chezmoi-update.timer" ]; then
  echo "❌ chezmoi-update.timer was not enabled by the expected symlink"
  exit 1
fi
echo "✅ chezmoi updater systemd units deployed"

if ! grep -Fq '"diffSidebarOpen": false' "$CLAUDE_GLOBAL_CONFIG"; then
  echo "❌ Claude diff sidebar setting was not disabled"
  exit 1
fi
if ! grep -Fq '"accountUuid": "keep-me"' "$CLAUDE_GLOBAL_CONFIG" \
  || ! grep -Fq '"hasTrustDialogAccepted": true' "$CLAUDE_GLOBAL_CONFIG"; then
  echo "❌ Claude global runtime state was not preserved"
  exit 1
fi
echo "✅ Claude diff sidebar disabled while global runtime state was preserved"

for target in "${STALE_TARGETS[@]}"; do
  if [ -e "$target" ] || [ -L "$target" ]; then
    echo "❌ stale managed target was not removed: $target"
    exit 1
  fi
done
if [ ! -f "$LOCAL_RUNTIME_FILE" ]; then
  echo "❌ intentionally unmanaged runtime file was removed"
  exit 1
fi
echo "✅ stale managed targets removed while local runtime file was preserved"

# 生成されたファイルの検証
if [ ! -f "$HOME/.bashrc" ]; then
  echo "❌ .bashrc not generated"
  exit 1
fi

if [ ! -d "$HOME/.bashrc.d" ]; then
  echo "❌ .bashrc.d directory not generated"
  exit 1
fi

echo "✅ Basic files generated successfully"

if [ ! -f "$HOME/.profile" ]; then
  echo "❌ .profile not generated"
  exit 1
fi

if ! grep -Fq 'mise activate bash --shims' "$HOME/.profile"; then
  echo "❌ .profile does not initialize mise shims"
  exit 1
fi

if [ ! -f "$HOME/.bash_env" ] || ! grep -Fq 'mise env -s bash' "$HOME/.bash_env"; then
  echo "❌ .bash_env does not initialize mise environments"
  exit 1
fi

if ! grep -Fq ". \"\$HOME/.profile\"" "$HOME/.bash_profile"; then
  echo "❌ .bash_profile does not load .profile"
  exit 1
fi

echo "✅ mise shims configured for login shells"

PROFILE_PATH=$(env -i HOME="$HOME" PATH="/usr/bin:/bin" sh -c ". \"\$HOME/.profile\"; printf '%s\n' \"\$PATH\"")
case "$PROFILE_PATH" in
  "$HOME/.local/bin:"*) ;;
  *)
    echo "❌ .profile does not prepend ~/.local/bin to PATH"
    exit 1
    ;;
esac
PROFILE_LOCAL_BIN_COUNT=$(printf '%s\n' "$PROFILE_PATH" | tr ':' '\n' | grep -Fxc "$HOME/.local/bin" || true)
if [ "$PROFILE_LOCAL_BIN_COUNT" -ne 1 ]; then
  echo "❌ .profile adds ~/.local/bin to PATH more than once"
  exit 1
fi

PROFILE_HOME_BIN_COUNT=$(printf '%s\n' "$PROFILE_PATH" | tr ':' '\n' | grep -Fxc "$HOME/bin" || true)
if [ "$PROFILE_HOME_BIN_COUNT" -ne 1 ]; then
  echo "❌ .profile must add ~/bin to PATH exactly once (found $PROFILE_HOME_BIN_COUNT)"
  exit 1
fi
case "$PROFILE_PATH" in
  *":$HOME/bin") ;;
  *)
    echo "❌ .profile must append ~/bin to the end of PATH so it cannot shadow system commands"
    exit 1
    ;;
esac

BASHRC_PATH=$(env -i HOME="$HOME" PATH="$HOME/.local/bin:/usr/bin:/bin" bash -c ". \"\$HOME/.bashrc.d/00-path.sh\"; printf '%s\n' \"\$PATH\"")
BASHRC_LOCAL_BIN_COUNT=$(printf '%s\n' "$BASHRC_PATH" | tr ':' '\n' | grep -Fxc "$HOME/.local/bin" || true)
if [ "$BASHRC_LOCAL_BIN_COUNT" -ne 1 ]; then
  echo "❌ .bashrc.d/00-path.sh duplicates ~/.local/bin in PATH"
  exit 1
fi
echo "✅ ~/.local/bin PATH setup is idempotent"

FAKE_MISE="$HOME/.local/bin/mise"
mkdir -p "$HOME/.local/bin" "$HOME/.local/share/mise/shims"
cat > "$FAKE_MISE" <<'FAKE_MISE'
#!/bin/sh
case "$*" in
  "activate bash --shims") printf 'export PATH="%s/.local/share/mise/shims:$PATH"\n' "$HOME" ;;
  "env -s bash") printf 'export MISE_CODEX_ENV=enabled\n' ;;
esac
FAKE_MISE
chmod +x "$FAKE_MISE"
# shellcheck disable=SC2016
NON_INTERACTIVE_ENV=$(env -i HOME="$HOME" PATH="/usr/bin:/bin" BASH_ENV="$HOME/.bash_env" bash -c 'printf "%s\n" "$MISE_CODEX_ENV"; printf "%s\n" "$PATH"')
if ! grep -Fxq 'enabled' <<< "$NON_INTERACTIVE_ENV" \
  || ! grep -Fq "$HOME/.local/share/mise/shims" <<< "$NON_INTERACTIVE_ENV"; then
  echo "❌ non-interactive Bash does not load mise environment"
  exit 1
fi
echo "✅ non-interactive Bash loads mise environment"

if [ ! -f "$HOME/.agents/skills/issue-pr/SKILL.md" ]; then
  echo "❌ Codex issue-pr skill not generated"
  exit 1
fi

if [ ! -x "$HOME/bin/gh-pr-target-repo.sh" ]; then
  echo "❌ gh-pr-target-repo helper not generated"
  exit 1
fi

if [ ! -x "$HOME/bin/gh-pr-reviewer.sh" ]; then
  echo "❌ gh-pr-reviewer helper not generated"
  exit 1
fi

if [ ! -x "$HOME/bin/powerline-daemon-launch.sh" ]; then
  echo "❌ powerline-daemon-launch helper not generated"
  exit 1
fi

if [ ! -x "$HOME/.agents/skills/pr-health-monitor/scripts/wait-for-copilot-review.sh" ]; then
  echo "❌ Codex Copilot review watcher script not generated"
  exit 1
fi

if [ ! -x "$HOME/.agents/skills/pr-health-monitor/scripts/pr-monitor-state.sh" ] \
  || [ ! -x "$HOME/.agents/skills/pr-health-monitor/scripts/watch-pr.sh" ] \
  || [ ! -f "$HOME/.agents/skills/resume-pr-monitor/SKILL.md" ]; then
  echo "❌ Durable Codex PR monitor files not generated"
  exit 1
fi

if [ ! -x "$HOME/.agents/skills/deep-review/scripts/ledger.sh" ] \
  || [ ! -x "$HOME/.agents/skills/deep-review/scripts/render-comment.sh" ] \
  || [ ! -x "$HOME/.agents/skills/deep-review/scripts/validate-comment.sh" ]; then
  echo "❌ deep-review helper scripts not generated or not executable"
  exit 1
fi

# Claude 側 deep-review スキルが ZIP インポート可能な自己完結構成で展開されることを確認する。
for f in scripts/ledger.sh scripts/render-comment.sh scripts/validate-comment.sh scripts/measure-usage.sh references/regression-cases.md; do
  if [ ! -f "$HOME/.claude/skills/deep-review/$f" ]; then
    echo "❌ Claude deep-review skill file not generated: $f"
    exit 1
  fi
done

echo "✅ Codex files generated successfully"

# Claude 側は pr-health-monitor に統合済み。旧 3 スキルが残らず、統合 Monitor スクリプトが配置されること。
for removed in handle-pr-reviews wait-for-copilot-review wait-for-pr-close; do
  if [ -e "$HOME/.claude/skills/$removed" ]; then
    echo "❌ Removed Claude skill still deployed: $HOME/.claude/skills/$removed"
    exit 1
  fi
done
if [ ! -f "$HOME/.claude/skills/pr-health-monitor/scripts/watch-pr-events.sh" ]; then
  echo "❌ Unified monitor script missing: ~/.claude/skills/pr-health-monitor/scripts/watch-pr-events.sh"
  exit 1
fi

echo "✅ Unified Claude PR monitor deployed and obsolete skills removed"

SUPERPOWERS_INVOCATIONS=(
  'superpowers:brainstorming'
  'superpowers:writing-plans'
  'superpowers:subagent-driven-development'
  'superpowers:executing-plans'
  'superpowers:verification-before-completion'
)
CLAUDE_WORKFLOW_SKILLS=(
  "$HOME/.claude/skills/issue-pr/SKILL.md"
  "$HOME/.claude/skills/issue-pr-deep/SKILL.md"
  "$HOME/.claude/skills/issue-pr-lite/SKILL.md"
  "$HOME/.claude/skills/glitchtip-pr/SKILL.md"
  "$HOME/.claude/skills/glitchtip-pr-deep/SKILL.md"
  "$HOME/.claude/skills/glitchtip-pr-lite/SKILL.md"
)

for skill in "${CLAUDE_WORKFLOW_SKILLS[@]}"; do
  if [ ! -f "$skill" ]; then
    echo "❌ Expected active Claude workflow skill not deployed: $skill"
    exit 1
  fi
  for invocation in "${SUPERPOWERS_INVOCATIONS[@]}"; do
    if grep -Fq "$invocation" "$skill"; then
      echo "❌ Stale $invocation invocation still present in $skill"
      exit 1
    fi
  done
done

for rule in "$HOME/.claude/rules/"*.md "$HOME/.claude/docs/"*.md; do
  for invocation in "${SUPERPOWERS_INVOCATIONS[@]}"; do
    if grep -Fq "$invocation" "$rule"; then
      echo "❌ Stale $invocation invocation still present in $rule"
      exit 1
    fi
  done
done

if [ -f "$HOME/.claude/rules/superpowers.md" ]; then
  echo "❌ deleted rules/superpowers.md still deployed"
  exit 1
fi

echo "✅ No superpowers: invocation remains in active Claude workflow"

# オンデマンド参照の workflow 系文書は docs/ にのみ展開され、常時ロードされる rules/ に残らないこと。
for doc in workflow workflow-sub-agents design-workflow issue-comment-docs; do
  if [ ! -f "$HOME/.claude/docs/$doc.md" ] || [ -f "$HOME/.claude/rules/$doc.md" ]; then
    echo "❌ $doc.md must be deployed under docs/ and not under rules/"
    exit 1
  fi
done

if [ ! -f "$HOME/.claude/skills/deep-review/reviewers/g-performance-errors-types.md" ] \
  || [ ! -f "$HOME/.agents/skills/deep-review/reviewers/g-performance-errors-types.md" ]; then
  echo "❌ merged reviewer g-performance-errors-types.md not deployed"
  exit 1
fi

echo "✅ On-demand docs and merged reviewers deployed at their new paths"

# Superpowers plugin が展開後 settings.json (private_settings.json から生成) で
# enabled でないこと。
CLAUDE_SETTINGS="$HOME/.claude/settings.json"
if [ ! -f "$CLAUDE_SETTINGS" ]; then
  echo "❌ Claude Code settings.json not deployed"
  exit 1
fi
if grep -Fq '"superpowers@claude-plugins-official"' "$CLAUDE_SETTINGS"; then
  echo "❌ superpowers@claude-plugins-official is still enabled in settings.json"
  exit 1
fi

echo "✅ Superpowers plugin not enabled in deployed settings.json"

# .agent-work/ と legacy な docs/superpowers/ / .superpowers/ が
# global gitignore に残っていること (移行期間中の後方互換)。
GLOBAL_GITIGNORE="$XDG_CONFIG_HOME/git/ignore"
if ! grep -Fxq '.agent-work/' "$GLOBAL_GITIGNORE" \
  || ! grep -Fxq 'docs/superpowers/' "$GLOBAL_GITIGNORE" \
  || ! grep -Fxq '.superpowers/' "$GLOBAL_GITIGNORE"; then
  echo "❌ global gitignore missing .agent-work/ or legacy superpowers entries"
  exit 1
fi

echo "✅ global gitignore excludes .agent-work/ and legacy superpowers paths"

# Codex はプロジェクト信頼やフック承認ハッシュを config.toml に保存する。chezmoi の
# modify_ テンプレートが管理対象の設定を反映しつつ、その実行時状態を保持することを確認する。
CODEX_CONFIG="$HOME/.codex/config.toml"
if [ ! -f "$CODEX_CONFIG" ]; then
  echo "❌ Codex config.toml not generated"
  exit 1
fi

sed -i '/^\[features\]$/a codex_hooks = false\nremote_control = true' "$CODEX_CONFIG"
sed -i '1i model = "gpt-5.4"' "$CODEX_CONFIG"
sed -i '1i model_reasoning_effort = "medium"' "$CODEX_CONFIG"
printf '\n[projects."/tmp/codex-runtime-state"]\ntrust_level = "trusted"\n[hooks.state."/tmp/codex-runtime-hook"]\ntrusted_hash = "sha256:test"\n[notice.model_migrations]\ngpt_5_4 = "gpt-5.6"\n' >> "$CODEX_CONFIG"
if ! "$CHEZMOI_BIN" apply --source="$SOURCE_DIR"; then
  echo "❌ chezmoi apply failed while preserving Codex runtime state"
  exit 1
fi

if ! grep -Fq 'web_search = "live"' "$CODEX_CONFIG" \
  || ! grep -Fq 'model = "gpt-5.4"' "$CODEX_CONFIG" \
  || ! grep -Fq 'model_reasoning_effort = "medium"' "$CODEX_CONFIG" \
  || ! grep -Fq 'hooks = true' "$CODEX_CONFIG" \
  || grep -Fq 'codex_hooks =' "$CODEX_CONFIG" \
  || ! grep -Fq 'remote_control = true' "$CODEX_CONFIG" \
  || ! grep -Fq 'BASH_ENV = "'"$HOME"'/.bash_env"' "$CODEX_CONFIG" \
  || ! grep -Fq 'trust_level = "trusted"' "$CODEX_CONFIG" \
  || ! grep -Fq 'trusted_hash = "sha256:test"' "$CODEX_CONFIG" \
  || ! grep -Fq 'gpt_5_4 = "gpt-5.6"' "$CODEX_CONFIG"; then
  echo "❌ Codex runtime state was not preserved"
  exit 1
fi

echo "✅ Codex runtime state preserved successfully"

# シークレットスキャン pre-commit フックの検証
if [ ! -x "$HOME/.config/git/hooks/pre-commit" ]; then
  echo "❌ pre-commit hook not generated or not executable"
  exit 1
fi

if [ ! -f "$HOME/.gitleaks.toml" ]; then
  echo "❌ .gitleaks.toml not generated"
  exit 1
fi

# git config --get はストア済みの生文字列を返し、~ はここでは展開されない (git 内部で
# フック解決時にのみ展開される) ため、リテラル文字列 "~/.config/git/hooks" と比較する
HOOKS_PATH_VALUE=$(git config --file "$HOME/.config/git/config" --get core.hooksPath || true)
# shellcheck disable=SC2088
if [ "$HOOKS_PATH_VALUE" != "~/.config/git/hooks" ]; then
  echo "❌ core.hooksPath not set to \$HOME/.config/git/hooks (got: $HOOKS_PATH_VALUE)"
  exit 1
fi

echo "✅ Secret scan pre-commit hook and hooksPath generated successfully"

# エンドツーエンド検証: 実際の git commit が core.hooksPath 経由でこのフックを起動すること
# (ユニットテストはフックスクリプトを bash 経由で直接呼び出すのみで、
# core.hooksPath の名前解決・実行権限を含む git 自身の起動経路は検証していないため)
HOOK_TEST_REPO=$(mktemp -d)
HOOK_MOCK_BIN=$(mktemp -d)
HOOK_INVOKED_MARKER=$(mktemp -u)
cat > "$HOOK_MOCK_BIN/gitleaks" << EOF
#!/bin/bash
touch "$HOOK_INVOKED_MARKER"
exit 0
EOF
chmod +x "$HOOK_MOCK_BIN/gitleaks"

(
  cd "$HOOK_TEST_REPO" || exit 1
  git init -q
  git config user.name "Test User"
  git config user.email "test@example.com"
  echo "content" > file.txt
  git add file.txt
  PATH="$HOOK_MOCK_BIN:$PATH" git commit -q -m "test commit"
)
HOOK_COMMIT_EXIT=$?

if [ "$HOOK_COMMIT_EXIT" -ne 0 ]; then
  echo "❌ git commit failed unexpectedly (exit $HOOK_COMMIT_EXIT)"
  rm -rf "$HOOK_TEST_REPO" "$HOOK_MOCK_BIN"
  exit 1
fi

if [ ! -f "$HOOK_INVOKED_MARKER" ]; then
  echo "❌ pre-commit hook was not invoked by git via core.hooksPath"
  rm -rf "$HOOK_TEST_REPO" "$HOOK_MOCK_BIN"
  exit 1
fi

rm -rf "$HOOK_TEST_REPO" "$HOOK_MOCK_BIN" "$HOOK_INVOKED_MARKER"
echo "✅ pre-commit hook invoked by git via core.hooksPath end-to-end"

CODEX_AGENT_FILES=(
  "spec_reviewer.toml"
  "plan_reviewer.toml"
  "container_status_checker.toml"
  "container_error_investigator.toml"
)

for agent_file in "${CODEX_AGENT_FILES[@]}"; do
  if [ ! -f "$HOME/.codex/agents/$agent_file" ]; then
    echo "❌ Codex agent definition not generated: $agent_file"
    exit 1
  fi
done

echo "✅ Codex agent definitions generated successfully"

# Idempotency テスト: 2 回目の apply で差分がないことを確認
echo "Testing idempotency..."
# .chezmoiscripts/ ディレクトリの変更は無視 (chezmoi の内部管理ファイル)
DIFF_OUTPUT=$("$CHEZMOI_BIN" diff --source="$SOURCE_DIR" 2>&1 | awk '
  BEGIN { skip = 0 }
  /^diff --git a\/.chezmoiscripts\// { skip = 1; next }
  /^diff --git/ { skip = 0 }
  !skip { print }
')
if [ -n "$DIFF_OUTPUT" ]; then
  echo "❌ Idempotency test failed: chezmoi diff showed changes after apply"
  echo "$DIFF_OUTPUT"
  exit 1
fi

echo "✅ Idempotency test passed"

# シンボリックリンクの整合性確認 (Claude Code フックのシンボリックリンク)
HOOKS_DIR="$HOME/.claude/hooks"
SYMLINKS=(
  "deep-review-immediate-fix.sh"
  "deep-review-require-fixes.sh"
  "require-review-thread-fixes.sh"
)

SYMLINK_CHECKED=0
for symlink in "${SYMLINKS[@]}"; do
  SYMLINK_PATH="$HOOKS_DIR/$symlink"
  if [ -L "$SYMLINK_PATH" ]; then
    TARGET=$(readlink "$SYMLINK_PATH")
    if [ ! -f "$HOOKS_DIR/$TARGET" ]; then
      echo "❌ Symlink broken: $symlink -> $TARGET"
      exit 1
    fi
    echo "✅ Symlink integrity verified: $symlink -> $TARGET"
    SYMLINK_CHECKED=$((SYMLINK_CHECKED + 1))
  fi
done

if [ $SYMLINK_CHECKED -gt 0 ]; then
  echo "✅ All $SYMLINK_CHECKED symlinks verified"
fi

# 環境変数テンプレートの検証
if [ -f "$HOME/.env.example" ] && [ ! -f "$HOME/.env" ]; then
  echo "✅ Template files correctly generated (not applied)"
fi

echo "✅ All integration tests passed"
