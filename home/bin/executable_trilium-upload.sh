#!/usr/bin/env bash
# Trilium へドキュメントをアップロードする(ETAPI 経由、pandoc で Markdown → HTML 変換)。
# 使い方: trilium-upload.sh <file-path> <slug> <title>
# 成功時は標準出力の最終行に共有 URL を出力する。
set -euo pipefail

if [ "$#" -ne 3 ]; then
  echo "Usage: trilium-upload.sh <file-path> <slug> <title>" >&2
  exit 1
fi

file="$1"
slug="$2"
title="$3"

if [ ! -f "$file" ]; then
  echo "ERROR: file not found: $file" >&2
  exit 1
fi

for cmd in pandoc curl jq; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "ERROR: $cmd is required but not installed" >&2
    exit 1
  fi
done

# ~/.env を読み込む(completion-notify 配下のスクリプト群と同じパターン)。
# shellcheck source=/dev/null
source "$HOME/.env"

if [ -z "${TRILIUM_HTTP_URL:-}" ] || [ -z "${TRILIUM_ETAPI_TOKEN:-}" ]; then
  echo "ERROR: TRILIUM_HTTP_URL / TRILIUM_ETAPI_TOKEN must be set in ~/.env" >&2
  exit 1
fi

# slug を ETAPI の noteId 形式([a-zA-Z0-9_]{4,32})に正規化する。
note_id=$(printf '%s' "$slug" | tr '-' '_' | tr -cd 'a-zA-Z0-9_' | cut -c1-32)
if [ "${#note_id}" -lt 4 ]; then
  echo "ERROR: slug too short after normalization to a valid Trilium noteId: $slug" >&2
  exit 1
fi

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

html_file="$tmpdir/content.html"
# raw_html 拡張を無効化し、Markdown 内に紛れた生 HTML(<script> 等)を
# エスケープする。"_share" 配下は公開閲覧可能になるため、生 HTML の
# そのままの通過を防ぐ。
pandoc -f markdown-raw_html --sandbox "$file" -o "$html_file"

auth_header="Authorization: $TRILIUM_ETAPI_TOKEN"
# このスクリプトが作成したノートであることの目印。noteId の衝突時に
# 無関係な既存ノートを誤って上書きしないためのラベル属性名。
marker_label="triliumUploadTool"

# 既存ノートかどうかを確認する。
note_json=$(curl -s -H "$auth_header" \
  "$TRILIUM_HTTP_URL/etapi/notes/$note_id")
get_status=$(curl -s -o /dev/null -w '%{http_code}' -H "$auth_header" \
  "$TRILIUM_HTTP_URL/etapi/notes/$note_id")

if [ "$get_status" = "200" ]; then
  # 衝突防止: マーカーラベルを持たないノートは他用途のノートとみなし、上書きを拒否する。
  # NOTE: ETAPI に単独の GET /etapi/notes/{id}/attributes エンドポイントは存在しない
  # (404 Router not found) ため、ノート本体のレスポンスに含まれる "attributes" フィールドを見る。
  if ! printf '%s' "$note_json" | jq -e --arg name "$marker_label" \
      '.attributes | any(.[]; .type == "label" and .name == $name)' >/dev/null; then
    echo "ERROR: note $note_id exists but lacks the $marker_label marker; refusing to overwrite a note this script did not create" >&2
    exit 1
  fi

  # 既存ノートを更新: title と content の両方を上書きする。
  title_payload=$(jq -n --arg title "$title" '{title: $title}')
  curl -sf -X PATCH -H "$auth_header" -H "Content-Type: application/json" \
    --data "$title_payload" \
    "$TRILIUM_HTTP_URL/etapi/notes/$note_id" >/dev/null
  curl -sf -X PUT -H "$auth_header" -H "Content-Type: text/plain" \
    --data-binary "@$html_file" \
    "$TRILIUM_HTTP_URL/etapi/notes/$note_id/content" >/dev/null
elif [ "$get_status" = "404" ]; then
  # 新規作成: "_share" の直下に、noteId を明示指定して作成する。
  # → "_share" の子孫に配置されたノートは自動的に共有(公開閲覧可能)になる。
  # NOTE: ETAPI の create-note は "attributes" プロパティを受け付けない
  # (PROPERTY_NOT_ALLOWED) ため、マーカーラベルはノート作成後に
  # 別途 POST /etapi/attributes で付与する。
  # NOTE: --arg content "$(cat "$html_file")" だと本文がコマンドライン引数として
  # 渡され、大きいドキュメントで "Argument list too long" になる。--rawfile で
  # ファイルから直接読み込むことで引数長制限を回避する。
  payload_file="$tmpdir/create-note-payload.json"
  jq -n \
    --arg noteId "$note_id" \
    --arg title "$title" \
    --rawfile content "$html_file" \
    '{parentNoteId: "_share", noteId: $noteId, title: $title, type: "text", content: $content}' \
    > "$payload_file"
  # NOTE: 同様に、curl --data "$payload" のようにシェル変数展開でコマンドライン
  # 引数として渡すと大きいドキュメントで "Argument list too long" になるため、
  # --data @<file> でファイルから直接読み込む。
  curl -sf -X POST -H "$auth_header" -H "Content-Type: application/json" \
    --data "@$payload_file" \
    "$TRILIUM_HTTP_URL/etapi/create-note" >/dev/null

  label_payload=$(jq -n \
    --arg noteId "$note_id" \
    --arg markerLabel "$marker_label" \
    '{noteId: $noteId, type: "label", name: $markerLabel, value: "1"}')
  curl -sf -X POST -H "$auth_header" -H "Content-Type: application/json" \
    --data "$label_payload" \
    "$TRILIUM_HTTP_URL/etapi/attributes" >/dev/null
else
  echo "ERROR: unexpected status $get_status from Trilium existence check ($TRILIUM_HTTP_URL/etapi/notes/$note_id)" >&2
  exit 1
fi

echo "$TRILIUM_HTTP_URL/share/$note_id"
