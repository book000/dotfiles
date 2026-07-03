#!/bin/bash
# AI エージェント設定ファイルの JSON Schema バリデーション

set -euo pipefail

echo "Validating AI agent configuration files..."

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

# Codex CLI hooks.json
if [ -f "home/dot_codex/hooks.json" ]; then
  echo "Validating Codex CLI hooks.json..."
  if ! jq empty home/dot_codex/hooks.json; then
    echo "❌ Codex CLI hooks.json validation failed"
    FAILED=1
  else
    echo "✅ Codex CLI hooks.json validation passed"
  fi
  FILES_CHECKED=$((FILES_CHECKED + 1))
fi

# Codex CLI config.toml
if [ -f "home/dot_codex/config.toml" ]; then
  echo "Validating Codex CLI config.toml..."
  if ! python3 - <<'PY'
import pathlib

try:
    import tomllib
except ModuleNotFoundError:
    try:
        import tomli as tomllib
    except ModuleNotFoundError:
        raise SystemExit("tomllib or tomli is required to validate TOML but is not installed.")

with pathlib.Path("home/dot_codex/config.toml").open("rb") as fh:
    tomllib.load(fh)
PY
  then
    echo "❌ Codex CLI config.toml validation failed"
    FAILED=1
  else
    echo "✅ Codex CLI config.toml validation passed"
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
