#!/bin/bash
# install.sh のユニットテスト (パラメータ化版)

set -euo pipefail

echo "Testing install.sh with parameters..."

# テスト 1: --help オプション
echo "Test 1: --help option"
HELP_OUTPUT=$(bash install.sh --help 2>&1)
if ! grep -q "使用方法" <<< "$HELP_OUTPUT"; then
  echo "❌ --help option test failed"
  exit 1
fi
echo "✅ --help option test passed"

# テスト 2: --dry-run オプション (環境チェックのみ)
echo "Test 2: --dry-run option"
# ANSI カラーコードを削除してから確認
DRY_RUN_OUTPUT=$(bash install.sh --dry-run --skip-interactive --skip-apt --skip-gh --skip-ghq --skip-mkwork --skip-roots --skip-mise --skip-gitleaks 2>&1 | sed 's/\x1b\[[0-9;]*m//g')
if ! grep -q "DRY RUN" <<< "$DRY_RUN_OUTPUT"; then
  echo "❌ --dry-run option test failed"
  exit 1
fi
echo "✅ --dry-run option test passed"

# テスト 2.5: --help が --skip-gitleaks を案内していること
echo "Test 2.5: --help mentions --skip-gitleaks"
if ! grep -q -- "--skip-gitleaks" <<< "$HELP_OUTPUT"; then
  echo "❌ --help does not mention --skip-gitleaks"
  exit 1
fi
echo "✅ --help mentions --skip-gitleaks"

# テスト 2.6: apt パッケージに libatomic1 が含まれること
echo "Test 2.6: apt packages include libatomic1"
APT_DRY_RUN=$(bash install.sh --dry-run --skip-interactive --skip-gh --skip-ghq --skip-mkwork --skip-roots --skip-mise --skip-gitleaks 2>&1 | sed 's/\x1b\[[0-9;]*m//g')
APT_INSTALL_LINE=$(grep -F "[DRY RUN] sudo apt install -y " <<< "$APT_DRY_RUN")
if ! grep -qw "libatomic1" <<< "$APT_INSTALL_LINE"; then
  echo "❌ apt package list does not include libatomic1"
  exit 1
fi
echo "✅ apt package list includes libatomic1"

# テスト 2.7: 開発用 CLI が mise config に宣言されていること
echo "Test 2.7: mise config includes development tools"
MISE_CONFIG="home/dot_config/mise/config.toml"
MISE_TOOLS=(maven ripgrep yq actionlint hadolint shfmt devcontainer-cli delta)
for tool in "${MISE_TOOLS[@]}"; do
  if ! grep -Eq "^\"?${tool}\"? = " "$MISE_CONFIG"; then
    echo "❌ mise config does not include $tool"
    exit 1
  fi
done
echo "✅ mise config includes development tools"

# テスト 2.7.1: mise 管理ツールに latest 指定が残っていないこと
echo "Test 2.7.1: mise config has no latest versions"
if grep -Eq '= "latest"$' "$MISE_CONFIG"; then
  echo "❌ mise config contains unpinned latest versions"
  grep -En '= "latest"$' "$MISE_CONFIG"
  exit 1
fi
echo "✅ mise config has no latest versions"

# テスト 2.8: install フローが開発用 CLI を mise 経由で導入すること
echo "Test 2.8: install flow installs development tools via mise"
MISE_DRY_RUN=$(bash install.sh --dry-run --skip-interactive --skip-apt --skip-gh --skip-ghq --skip-mkwork --skip-roots --skip-gitleaks 2>&1 | sed 's/\x1b\[[0-9;]*m//g')
MISE_DIRECT_TOOLS=(maven ripgrep yq actionlint hadolint shfmt delta)
for tool in "${MISE_DIRECT_TOOLS[@]}"; do
  if ! grep -Fq "[DRY RUN] mise install $tool" <<< "$MISE_DRY_RUN"; then
    echo "❌ install flow does not install $tool via mise"
    exit 1
  fi
done
if ! grep -Fq "[DRY RUN] mise install node" <<< "$MISE_DRY_RUN" \
  || ! grep -Fq "[DRY RUN] mise exec node -- mise install devcontainer-cli" <<< "$MISE_DRY_RUN"; then
  echo "❌ install flow does not bootstrap devcontainer-cli with mise-managed Node"
  exit 1
fi
echo "✅ install flow installs development tools via mise"

# テスト 3: 無効なオプション
echo "Test 3: invalid option"
# install.sh は無効なオプションで exit 1 を返すため、終了コードを無視
OUTPUT=$(bash install.sh --invalid-option 2>&1 || true)
if grep -q "Unknown option" <<< "$OUTPUT"; then
  echo "✅ invalid option test passed"
else
  echo "❌ invalid option test failed"
  exit 1
fi

echo "✅ All install.sh parameter tests passed"
