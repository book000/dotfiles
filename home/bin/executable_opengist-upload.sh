#!/usr/bin/env bash
# opengist へドキュメントをアップロードする(新規作成は HTTP push、更新は SSH push)。
# 使い方: opengist-upload.sh <file-path> <slug> <title>
# 成功時は標準出力の最終行に gist の URL を出力する。
set -euo pipefail

if [ "$#" -ne 3 ]; then
  echo "Usage: opengist-upload.sh <file-path> <slug> <title>" >&2
  exit 1
fi

file="$1"
slug="$2"
title="$3"

if [ ! -f "$file" ]; then
  echo "ERROR: file not found: $file" >&2
  exit 1
fi

# ~/.env を読み込む(トップレベルの横断的環境変数、home/dot_env.example 参照)。
# 新規作成(HTTP push)にのみ必要。
# shellcheck source=/dev/null
source "$HOME/.env"

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

ssh_remote="ssh://opengist/akubiusa/$slug"
push_output=""

if ssh -T -o BatchMode=yes -o ConnectTimeout=5 opengist true 2>/dev/null \
    && git clone -q "$ssh_remote" "$tmpdir/repo" 2>/dev/null; then
  # 既存 gist を更新: ファイルを上書きして通常 commit・push(fast-forward)。
  # → 履歴が自然に積み上がり、opengist の Web UI 上で改訂履歴を閲覧できる。
  cd "$tmpdir/repo"
  cp "$file" "./$(basename "$file")"
  git add .
  git commit -q -m "$title" --allow-empty
  push_output=$(git push origin main -o title="$title" -o visibility=private 2>&1)
else
  # 新規作成: SSH には gist 作成経路がないため HTTP push を使う(opengist のソースコード
  # 上、SSH は既存 gist への push/pull のみをサポートし、新規作成には対応していない)。
  # PAT は remote URL に埋め込まず、http.extraHeader で Basic 認証ヘッダーとして注入する。
  if [ -z "${OPENGIST_HTTP_URL:-}" ] || [ -z "${OPENGIST_API_TOKEN:-}" ]; then
    echo "ERROR: OPENGIST_HTTP_URL / OPENGIST_API_TOKEN must be set in ~/.env" >&2
    exit 1
  fi

  auth_header="Authorization: Basic $(printf '%s' "akubiusa:$OPENGIST_API_TOKEN" | base64 -w0)"
  http_remote="$OPENGIST_HTTP_URL/akubiusa/$slug"

  mkdir -p "$tmpdir/repo"
  cd "$tmpdir/repo"
  cp "$file" "./$(basename "$file")"
  git init -q -b main
  git add .
  git commit -q -m "$title"
  git remote add origin "$http_remote"
  push_output=$(git -c http.extraHeader="$auth_header" push origin main -o title="$title" -o visibility=private 2>&1)
fi

# gist URL を push 出力から抽出する。
# NOTE: 抽出パターンは実装時点で未検証。opengist の実際の push 出力形式に
# 応じて実機で確認・調整が必要(spec の「実装時に検証が必要な項目」参照)。
gist_url=$(echo "$push_output" | grep -oE 'https?://[^[:space:]]+' | tail -n 1 || true)

if [ -z "$gist_url" ]; then
  echo "ERROR: failed to extract gist URL from push output:" >&2
  echo "$push_output" >&2
  exit 1
fi

echo "$gist_url"
