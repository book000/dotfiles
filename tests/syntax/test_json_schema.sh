#!/bin/bash
# AI エージェント設定ファイルの JSON Schema バリデーション

set -euo pipefail

echo "Validating AI agent configuration files..."

# Codex の modify_ テンプレートを評価するため chezmoi を用意する。
if ! command -v chezmoi &> /dev/null; then
  CHEZMOI_BIN_DIR=$(mktemp -d)
  trap 'rm -rf "$CHEZMOI_BIN_DIR"' EXIT
  curl -sfL https://git.io/chezmoi | sh -s -- -b "$CHEZMOI_BIN_DIR"
  PATH="$CHEZMOI_BIN_DIR:$PATH"
fi

# check-jsonschema のインストール確認
if ! command -v check-jsonschema &> /dev/null; then
  echo "Installing check-jsonschema..."
  pip install check-jsonschema
fi

FAILED=0
FILES_CHECKED=0

# Claude Code settings.json (公式スキーマを使用)
if [ -f "home/dot_claude/settings.json" ]; then
  echo "Validating Claude Code settings.json..."
  if ! check-jsonschema --schemafile https://json.schemastore.org/claude-code-settings.json home/dot_claude/settings.json; then
    echo "❌ Claude Code settings.json validation failed"
    FAILED=1
  else
    echo "✅ Claude Code settings.json validation passed"
  fi
  FILES_CHECKED=$((FILES_CHECKED + 1))
fi

# Codex CLI config.toml modify template
if [ -f "home/dot_codex/modify_config.toml" ]; then
  echo "Validating Codex CLI config.toml..."
  CODEX_CONFIG_INPUT=$(mktemp)
  trap 'rm -rf "${CHEZMOI_BIN_DIR:-}" "$CODEX_CONFIG_INPUT"' EXIT
  printf '%s\n' \
    'web_search = "disabled"' \
    'model = "gpt-5.4"' \
    'model_reasoning_effort = "medium"' \
    '[projects."/tmp/codex-runtime-state"]' \
    'trust_level = "trusted"' \
    '[hooks.state."/tmp/codex-runtime-hook"]' \
    'trusted_hash = "sha256:test"' \
    '[notice.model_migrations]' \
    'gpt_5_4 = "gpt-5.6"' \
    '[features]' \
    'codex_hooks = false' \
    'remote_control = true' > "$CODEX_CONFIG_INPUT"
  if ! chezmoi execute-template --file --with-stdin home/dot_codex/modify_config.toml < "$CODEX_CONFIG_INPUT" | python3 -c '
import sys

try:
    import tomllib
except ModuleNotFoundError:
    try:
        import tomli as tomllib
    except ModuleNotFoundError:
        raise SystemExit("tomllib or tomli is required to validate TOML but is not installed.")

config = tomllib.loads(sys.stdin.read())
assert config["web_search"] == "live"
assert config["model"] == "gpt-5.4"
assert config["model_reasoning_effort"] == "medium"
assert config["features"]["hooks"] is True
assert config["features"]["remote_control"] is True
assert "codex_hooks" not in config["features"]
assert config["projects"]["/tmp/codex-runtime-state"]["trust_level"] == "trusted"
assert config["hooks"]["state"]["/tmp/codex-runtime-hook"]["trusted_hash"] == "sha256:test"
assert config["notice"]["model_migrations"]["gpt_5_4"] == "gpt-5.6"
'
  then
    echo "❌ Codex CLI config.toml validation failed"
    FAILED=1
  else
    echo "✅ Codex CLI config.toml validation passed"
  fi
  FILES_CHECKED=$((FILES_CHECKED + 1))
fi

# Renovate が chezmoi source state の mise config を対象にすること
if [ -f "renovate.json" ]; then
  echo "Validating Renovate mise manager file pattern..."
  if ! python3 - <<'PYRENOVATE'
import json
from pathlib import Path

config = json.loads(Path("renovate.json").read_text())
patterns = config.get("mise", {}).get("managerFilePatterns", [])
assert r'/^home/dot_config/mise/config\.toml$/' in patterns
PYRENOVATE
  then
    echo "❌ Renovate mise manager does not include chezmoi source config"
    FAILED=1
  else
    echo "✅ Renovate mise manager includes chezmoi source config"
  fi
  FILES_CHECKED=$((FILES_CHECKED + 1))
fi

# 検証対象のファイルが存在しない場合はエラー
if [ $FILES_CHECKED -eq 0 ]; then
  echo "❌ No AI agent configuration files found to validate"
  exit 1
fi

echo "✅ All $FILES_CHECKED AI agent configuration files validated"
exit $FAILED
