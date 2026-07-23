#!/bin/bash
# list-compose-dirs.sh のユニットテスト

set -euo pipefail

echo "Testing list-compose-dirs.sh..."

FAILED=0
SCRIPT="home/dot_claude/skills/check-container-status/scripts/executable_list-compose-dirs.sh"

if [ ! -f "$SCRIPT" ]; then
  echo "❌ Script not found: $SCRIPT"
  exit 1
fi

TEST_DIR=$(mktemp -d)
# shellcheck disable=SC2317,SC2329
cleanup() {
  rm -rf "$TEST_DIR"
}
trap cleanup EXIT

# 後述の配列に列挙されたファイル名パターンをそれぞれ単独で持つディレクトリ
mkdir -p "$TEST_DIR/proj-compose-yaml"
touch "$TEST_DIR/proj-compose-yaml/compose.yaml"

mkdir -p "$TEST_DIR/proj-compose-yml"
touch "$TEST_DIR/proj-compose-yml/compose.yml"

mkdir -p "$TEST_DIR/proj-docker-compose-yaml"
touch "$TEST_DIR/proj-docker-compose-yaml/docker-compose.yaml"

mkdir -p "$TEST_DIR/proj-docker-compose-yml"
touch "$TEST_DIR/proj-docker-compose-yml/docker-compose.yml"

# Compose 定義を持たないディレクトリ(誤検出しないことの確認)
mkdir -p "$TEST_DIR/proj-no-compose"
touch "$TEST_DIR/proj-no-compose/README.md"

# 複数の Compose ファイル名パターンを同時に持つディレクトリ(重複出力しないことの確認)
mkdir -p "$TEST_DIR/proj-duplicate-compose"
touch "$TEST_DIR/proj-duplicate-compose/compose.yaml"
touch "$TEST_DIR/proj-duplicate-compose/docker-compose.yml"

# サブディレクトリを持たない空の対象ディレクトリのテスト用
EMPTY_DIR=$(mktemp -d)

echo "Test 1: explicit target directory argument"
ACTUAL=$(bash "$SCRIPT" "$TEST_DIR" | sort)
EXPECTED=$(printf '%s\n' \
  "$TEST_DIR/proj-compose-yaml" \
  "$TEST_DIR/proj-compose-yml" \
  "$TEST_DIR/proj-docker-compose-yaml" \
  "$TEST_DIR/proj-docker-compose-yml" \
  "$TEST_DIR/proj-duplicate-compose" | sort)

if [ "$ACTUAL" = "$EXPECTED" ]; then
  echo "✅ explicit target directory argument test passed"
else
  echo "❌ explicit target directory argument test failed"
  echo "--- expected ---"
  echo "$EXPECTED"
  echo "--- actual ---"
  echo "$ACTUAL"
  FAILED=1
fi

echo "Test 2: default argument (current directory)"
ACTUAL=$(cd "$TEST_DIR" && bash "$OLDPWD/$SCRIPT" | sort)
if [ "$ACTUAL" = "$EXPECTED" ]; then
  echo "✅ default argument (cwd) test passed"
else
  echo "❌ default argument (cwd) test failed"
  FAILED=1
fi

echo "Test 3: directory with no compose subdirectories"
ACTUAL=$(bash "$SCRIPT" "$EMPTY_DIR")
rm -rf "$EMPTY_DIR"
if [ -z "$ACTUAL" ]; then
  echo "✅ empty target directory test passed"
else
  echo "❌ empty target directory test failed (expected no output, got: $ACTUAL)"
  FAILED=1
fi

echo "Test 4: nonexistent target directory"
if OUTPUT=$(bash "$SCRIPT" "$TEST_DIR/does-not-exist" 2>&1); then
  echo "❌ nonexistent target directory test failed (expected non-zero exit)"
  FAILED=1
else
  if echo "$OUTPUT" | grep -q "ERROR: not a directory"; then
    echo "✅ nonexistent target directory test passed"
  else
    echo "❌ nonexistent target directory test failed (missing error message): $OUTPUT"
    FAILED=1
  fi
fi

echo "Test 5: directory with multiple Compose filename patterns at once"
ACTUAL=$(bash "$SCRIPT" "$TEST_DIR" | grep -c "^$TEST_DIR/proj-duplicate-compose\$")
if [ "$ACTUAL" = "1" ]; then
  echo "✅ duplicate compose filenames test passed"
else
  echo "❌ duplicate compose filenames test failed (expected exactly 1 line, got: $ACTUAL)"
  FAILED=1
fi

exit $FAILED
