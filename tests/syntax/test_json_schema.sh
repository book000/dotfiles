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

# Gemini CLI settings.json (公式スキーマを使用)
# 注意: Gemini CLI が書き出すフィールド（previewFeatures など）が公式スキーマに
#       未定義の場合があるため、general セクションの additionalProperties 制約を緩和する
if [ -f "home/dot_gemini/settings.json" ]; then
  echo "Validating Gemini CLI settings.json..."
  GEMINI_SCHEMA_URL="https://raw.githubusercontent.com/google-gemini/gemini-cli/main/schemas/settings.schema.json"
  GEMINI_SCHEMA_TMP="$(mktemp /tmp/gemini-settings-schema.XXXXXX.json)"
  # スキーマをダウンロードし、general セクションの additionalProperties 制約を除去
  # （Gemini CLI 自身が出力するフィールドを許容するため）
  curl -s "$GEMINI_SCHEMA_URL" | python3 -c "
import json, sys
schema = json.load(sys.stdin)
general = schema.get('properties', {}).get('general', {})
general.pop('additionalProperties', None)
json.dump(schema, sys.stdout)
" > "$GEMINI_SCHEMA_TMP"
  if ! check-jsonschema --schemafile "$GEMINI_SCHEMA_TMP" home/dot_gemini/settings.json; then
    echo "❌ Gemini CLI settings.json validation failed"
    FAILED=1
  else
    echo "✅ Gemini CLI settings.json validation passed"
  fi
  rm -f "$GEMINI_SCHEMA_TMP"
  FILES_CHECKED=$((FILES_CHECKED + 1))
fi

# 検証対象のファイルが存在しない場合はエラー
if [ $FILES_CHECKED -eq 0 ]; then
  echo "❌ No AI agent configuration files found to validate"
  exit 1
fi

echo "✅ All $FILES_CHECKED AI agent configuration files validated"
exit $FAILED
