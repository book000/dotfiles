#!/bin/bash
# install.sh のユニットテスト (パラメータ化版)

set -euo pipefail

echo "Testing install.sh with parameters..."

# テスト 1: --help オプション
echo "Test 1: --help option"
if ! bash install.sh --help 2>&1 | grep -q "使用方法"; then
  echo "❌ --help option test failed"
  exit 1
fi
echo "✅ --help option test passed"

# テスト 2: --dry-run オプション (環境チェックのみ)
echo "Test 2: --dry-run option"
# ANSI カラーコードを削除してから grep
if ! bash install.sh --dry-run --skip-interactive --skip-apt --skip-gh --skip-ghq --skip-mkwork --skip-roots --skip-gitleaks 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep -q "DRY RUN"; then
  echo "❌ --dry-run option test failed"
  exit 1
fi
echo "✅ --dry-run option test passed"

# テスト 2.5: --help が --skip-gitleaks を案内していること
echo "Test 2.5: --help mentions --skip-gitleaks"
if ! bash install.sh --help 2>&1 | grep -q -- "--skip-gitleaks"; then
  echo "❌ --help does not mention --skip-gitleaks"
  exit 1
fi
echo "✅ --help mentions --skip-gitleaks"

# テスト 3: 無効なオプション
echo "Test 3: invalid option"
# install.sh は無効なオプションで exit 1 を返すため、終了コードを無視
OUTPUT=$(bash install.sh --invalid-option 2>&1 || true)
if echo "$OUTPUT" | grep -q "Unknown option"; then
  echo "✅ invalid option test passed"
else
  echo "❌ invalid option test failed"
  exit 1
fi

echo "✅ All install.sh parameter tests passed"
