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
