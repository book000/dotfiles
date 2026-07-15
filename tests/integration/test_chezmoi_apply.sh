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
  curl -sfL https://git.io/chezmoi | sh -s -- -b "$TEST_HOME/bin"
  CHEZMOI_BIN="$TEST_HOME/bin/chezmoi"
fi

# chezmoi を初期化
# .chezmoiroot ファイルが存在するため、リポジトリルート全体をソースとして指定
SOURCE_DIR="$(pwd)"
"$CHEZMOI_BIN" init --source="$SOURCE_DIR"

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

if [ ! -f "$HOME/.agents/skills/issue-pr/SKILL.md" ]; then
  echo "❌ Codex issue-pr skill not generated"
  exit 1
fi

if [ ! -x "$HOME/bin/gh-pr-target-repo.sh" ]; then
  echo "❌ gh-pr-target-repo helper not generated"
  exit 1
fi

if [ ! -x "$HOME/.agents/skills/pr-health-monitor/scripts/wait-for-copilot-review.sh" ]; then
  echo "❌ Codex Copilot review watcher script not generated"
  exit 1
fi

echo "✅ Codex files generated successfully"

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

if [ ! -f "$HOME/.claude/agents/spec-reviewer.md" ]; then
  echo "❌ spec-reviewer agent definition not generated"
  exit 1
fi

if [ ! -f "$HOME/.claude/agents/plan-reviewer.md" ]; then
  echo "❌ plan-reviewer agent definition not generated"
  exit 1
fi

echo "✅ spec-reviewer / plan-reviewer agent definitions generated successfully"

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
  "code-review-immediate-fix.sh"
  "require-code-review-fixes.sh"
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
