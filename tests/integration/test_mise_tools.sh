#!/bin/bash
# mise で固定した CLI を clean HOME に導入し、実バイナリを起動できることを確認する
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "$0")/../.." && pwd)
CONFIG="$REPO_ROOT/home/dot_config/mise/config.toml"
MISE_VERSION=$(sed -n 's/^MISE_VERSION="\(v[0-9.]*\)"$/\1/p' "$REPO_ROOT/install.sh")
if [[ -z "$MISE_VERSION" ]]; then
  echo "❌ mise version is not pinned in install.sh"
  exit 1
fi

TEST_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME"' EXIT
export HOME="$TEST_HOME"
export PATH="$HOME/.local/bin:$PATH"
export MISE_GLOBAL_CONFIG_FILE="$CONFIG"

curl -fsSL https://mise.run | MISE_VERSION="$MISE_VERSION" sh

# npm backend の devcontainer-cli と Maven の実行依存を先に用意する。
mise install node java
mise install pnpm ghq gh github:k1LoW/roots gitleaks \
  maven ripgrep yq actionlint hadolint shfmt devcontainer-cli delta

checks=(
  "pnpm|pnpm --version"
  "gh|gh --version"
  "ghq|ghq --version"
  "github:k1LoW/roots|roots --version"
  "gitleaks|gitleaks version"
  "java,maven|mvn --version"
  "ripgrep|rg --version"
  "yq|yq --version"
  "actionlint|actionlint --version"
  "hadolint|hadolint --version"
  "shfmt|shfmt --version"
  "node,devcontainer-cli|devcontainer --version"
  "delta|delta --version"
)

for check in "${checks[@]}"; do
  tools=${check%%|*}
  command=${check#*|}
  IFS=',' read -ra tool_args <<< "$tools"
  echo "Smoke testing: $command"
  mise exec "${tool_args[@]}" -- bash -lc "$command >/dev/null"
done

echo "✅ All pinned mise CLI smoke tests passed"
