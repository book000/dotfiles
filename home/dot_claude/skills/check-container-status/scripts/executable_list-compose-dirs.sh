#!/bin/bash
# Docker Compose 定義ファイルを持つディレクトリを列挙する
#
# 使用法: list-compose-dirs.sh [対象ディレクトリ]
#   対象ディレクトリを省略した場合はカレントディレクトリを使う。
# 対象ディレクトリ直下のサブディレクトリのうち、以下いずれかの Compose 定義ファイルを持つものを絶対パスで1行1件、標準出力へ列挙する。
#   compose.yaml / compose.yml / docker-compose.yaml / docker-compose.yml
# (Docker 公式の探索順序 https://docs.docker.com/compose/intro/compose-application-model/ に含まれる、後述の配列に列挙されたファイル名パターンのみを対象とする)

set -euo pipefail

TARGET_DIR="${1:-.}"

if [ ! -d "$TARGET_DIR" ]; then
  echo "ERROR: not a directory: $TARGET_DIR" >&2
  exit 1
fi

TARGET_DIR="$(cd "$TARGET_DIR" && pwd)"

COMPOSE_FILENAMES=(
  "compose.yaml"
  "compose.yml"
  "docker-compose.yaml"
  "docker-compose.yml"
)

for dir in "$TARGET_DIR"/*/; do
  [ -d "$dir" ] || continue
  dir="${dir%/}"
  for filename in "${COMPOSE_FILENAMES[@]}"; do
    if [ -f "$dir/$filename" ]; then
      echo "$dir"
      break
    fi
  done
done
