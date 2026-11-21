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

# テスト 2.6: apt が非対話かつ conffile 保持で実行され、パッケージに libatomic1 が含まれること
echo "Test 2.6: apt runs non-interactively, keeps conffiles, and includes libatomic1"
APT_DRY_RUN=$(bash install.sh --dry-run --skip-interactive --skip-gh --skip-ghq --skip-mkwork --skip-roots --skip-mise --skip-gitleaks 2>&1 | sed 's/\x1b\[[0-9;]*m//g')
APT_UPDATE_LINE=$(grep -F "[DRY RUN] sudo env DEBIAN_FRONTEND=noninteractive apt update" <<< "$APT_DRY_RUN")
if [[ -z "$APT_UPDATE_LINE" ]]; then
  echo "❌ apt update is not run with DEBIAN_FRONTEND=noninteractive"
  exit 1
fi
APT_INSTALL_LINE=$(grep -F "[DRY RUN] sudo env DEBIAN_FRONTEND=noninteractive apt install -y " <<< "$APT_DRY_RUN")
if [[ -z "$APT_INSTALL_LINE" ]]; then
  echo "❌ apt install is not run with DEBIAN_FRONTEND=noninteractive"
  exit 1
fi
for expected in "libatomic1" "-o Dpkg::Options::=--force-confdef" "-o Dpkg::Options::=--force-confold"; do
  if ! grep -qF -- "$expected" <<< "$APT_INSTALL_LINE"; then
    echo "❌ apt install line does not include: $expected"
    exit 1
  fi
done
echo "✅ apt runs non-interactively, keeps conffiles, and includes libatomic1"

# テスト 2.7: 開発用 CLI が mise config に宣言されていること
echo "Test 2.7: mise config includes development tools"
MISE_CONFIG="home/dot_config/mise/config.toml"
MISE_TOOLS=(maven ripgrep yq github:jdx/jactionlint hadolint shfmt devcontainer-cli delta lazydocker oxker "npm:ccstatusline")
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

# テスト 2.7.2: mise 管理 CLI の smoke test が Integration Test で実行されること
echo "Test 2.7.2: integration workflow runs mise CLI smoke test"
if ! grep -Fq "bash tests/integration/test_mise_tools.sh" .github/workflows/integration-test.yml; then
  echo "❌ integration workflow does not run mise CLI smoke test"
  exit 1
fi
echo "✅ integration workflow runs mise CLI smoke test"

# テスト 2.8: install フローが開発用 CLI を mise 経由で導入すること
echo "Test 2.8: install flow installs development tools via mise"
MISE_DRY_RUN=$(bash install.sh --dry-run --skip-interactive --skip-apt --skip-gh --skip-ghq --skip-mkwork --skip-roots --skip-gitleaks 2>&1 | sed 's/\x1b\[[0-9;]*m//g')
MISE_DIRECT_TOOLS=(maven ripgrep yq github:jdx/jactionlint hadolint shfmt delta lazydocker oxker)
for tool in "${MISE_DIRECT_TOOLS[@]}"; do
  if ! grep -Fq "[DRY RUN] mise install $tool" <<< "$MISE_DRY_RUN"; then
    echo "❌ install flow does not install $tool via mise"
    exit 1
  fi
done
if ! grep -Fq "[DRY RUN] mise install node" <<< "$MISE_DRY_RUN" \
  || ! grep -Fq "[DRY RUN] mise exec node -- mise install devcontainer-cli" <<< "$MISE_DRY_RUN" \
  || ! grep -Fq "[DRY RUN] mise exec node -- mise install npm:ccstatusline" <<< "$MISE_DRY_RUN"; then
  echo "❌ install flow does not bootstrap devcontainer-cli/ccstatusline with mise-managed Node"
  exit 1
fi
echo "✅ install flow installs development tools via mise"

# テスト 2.9: 既存 mise が固定版と異なる場合はインストーラを再実行し、一致する場合は何もしないこと
echo "Test 2.9: install_mise reinstalls only when the installed mise differs from MISE_VERSION"
PINNED_MISE_VERSION=$(sed -n 's/^MISE_VERSION="\(v[0-9.]*\)"$/\1/p' install.sh)
if [[ -z "$PINNED_MISE_VERSION" ]]; then
  echo "❌ MISE_VERSION was not found in install.sh"
  exit 1
fi
MISE_STUB_DIR=$(mktemp -d)
trap 'rm -rf "$MISE_STUB_DIR"' EXIT
# BASH_ENV が bash 起動ごとに mise を呼ぶ環境で再帰しないよう、スタブは sh で書き BASH_ENV を外して実行する
make_mise_stub() {
  printf '#!/bin/sh\necho "%s linux-x64 (2026-01-01)"\n' "$1" > "$MISE_STUB_DIR/mise"
  chmod +x "$MISE_STUB_DIR/mise"
}
run_install_mise_dry_run() {
  env -u BASH_ENV PATH="$MISE_STUB_DIR:$PATH" bash install.sh --dry-run --skip-interactive --skip-apt --skip-gh --skip-ghq --skip-mkwork --skip-roots --skip-gitleaks 2>&1 | sed 's/\x1b\[[0-9;]*m//g'
}

make_mise_stub "2026.8.5"
STALE_OUTPUT=$(run_install_mise_dry_run)
for expected in \
  "mise を 2026.8.5 から ${PINNED_MISE_VERSION#v} に更新します" \
  "[DRY RUN] curl -fsSL --retry 5 --retry-delay 5 https://mise.run | MISE_VERSION=$PINNED_MISE_VERSION sh" \
  "PATH 上の mise ($MISE_STUB_DIR/mise) は $HOME/.local/bin/mise ではないため"; do
  if ! grep -Fq -- "$expected" <<< "$STALE_OUTPUT"; then
    echo "❌ stale mise output does not include: $expected"
    exit 1
  fi
done

make_mise_stub "${PINNED_MISE_VERSION#v}"
CURRENT_OUTPUT=$(run_install_mise_dry_run)
if ! grep -Fq "mise は既にインストールされています (${PINNED_MISE_VERSION#v} linux-x64" <<< "$CURRENT_OUTPUT"; then
  echo "❌ up-to-date mise is not reported as already installed"
  exit 1
fi
if grep -Fq "MISE_VERSION=$PINNED_MISE_VERSION sh" <<< "$CURRENT_OUTPUT"; then
  echo "❌ up-to-date mise triggers the installer"
  exit 1
fi
echo "✅ install_mise reinstalls only when the installed mise differs from MISE_VERSION"

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
