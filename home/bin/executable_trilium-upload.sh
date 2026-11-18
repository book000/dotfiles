#!/usr/bin/env bash
# Trilium へドキュメントをアップロードする(ETAPI 経由、pandoc で Markdown → HTML 変換)。
# 使い方: trilium-upload.sh <file-path> <noteId> <topic> <docType> <title> [--folder-title <title>]
# 成功時は標準出力の最終行に共有 URL を出力する。
set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=/dev/null
source "$script_dir/trilium-common.sh"

usage() {
  echo "Usage: trilium-upload.sh <file-path> <noteId> <topic> <docType> <title> [--folder-title <title>]" >&2
  exit 1
}

if [ "$#" -lt 5 ]; then
  usage
fi

file="$1"
note_id="$2"
topic="$3"
doc_type="$4"
title="$5"
shift 5

folder_title=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --folder-title)
      [ "$#" -ge 2 ] || usage
      folder_title="$2"
      shift 2
      ;;
    *)
      usage
      ;;
  esac
done

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

trilium_load_env
trilium_validate_id "$note_id" "noteId"
trilium_validate_topic "$topic"
trilium_validate_doc_type "$doc_type"

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
  # 例外: 新規作成直後に marker 付与が失敗したノート(トピックのフォルダ配下で属性なし)は
  # このスクリプトが作成したものとして復旧する。
  if ! printf '%s' "$note_json" | jq -e --arg name "$marker_label" \
      '.attributes | any(.[]; .type == "label" and .name == $name)' >/dev/null; then
    if trilium_is_unmarked_upload_orphan "$note_json" "$(trilium_folder_id "$topic")"; then
      echo "NOTE: note $note_id has no $marker_label marker but looks like an interrupted upload by this script; recovering" >&2
    else
      echo "ERROR: note $note_id exists but lacks the $marker_label marker; refusing to overwrite a note this script did not create" >&2
      exit 1
    fi
  fi

  # 既存ノートを更新: title と content の両方を上書きする。
  title_payload=$(jq -n --arg title "$title" '{title: $title}')
  curl -sf -X PATCH -H "$auth_header" -H "Content-Type: application/json" \
    --data "$title_payload" \
    "$TRILIUM_HTTP_URL/etapi/notes/$note_id" >/dev/null
  curl -sf -X PUT -H "$auth_header" -H "Content-Type: text/plain" \
    --data-binary "@$html_file" \
    "$TRILIUM_HTTP_URL/etapi/notes/$note_id/content" >/dev/null

  # リファクタ前に作成された既存ノートには topic/docType/marker ラベルが
  # 付与されていない場合があるため、不足していれば補完する(冪等)。
  for label_name in "$marker_label" "docType" "topic"; do
    case "$label_name" in
      "$marker_label") label_value="1" ;;
      docType) label_value="$doc_type" ;;
      topic) label_value="$topic" ;;
    esac
    trilium_upsert_label "$note_json" "$note_id" "$label_name" "$label_value" "$auth_header" "$TRILIUM_HTTP_URL"
  done
elif [ "$get_status" = "404" ]; then
  # 新規作成: トピック単位のフォルダノート配下に、noteId を明示指定して作成する。
  # フォルダは "_share" の子孫のため、フォルダ配下のノートも自動的に共有される。
  folder_id=$(trilium_resolve_folder "$topic" "$folder_title")

  # NOTE: ETAPI の create-note は "attributes" プロパティを受け付けない
  # (PROPERTY_NOT_ALLOWED) ため、メタデータラベルはノート作成後に
  # 別途 POST /etapi/attributes で付与する。
  # NOTE: --arg content "$(cat "$html_file")" だと本文がコマンドライン引数として
  # 渡され、大きいドキュメントで "Argument list too long" になる。--rawfile で
  # ファイルから直接読み込むことで引数長制限を回避する。
  payload_file="$tmpdir/create-note-payload.json"
  jq -n \
    --arg parentNoteId "$folder_id" \
    --arg noteId "$note_id" \
    --arg title "$title" \
    --rawfile content "$html_file" \
    '{parentNoteId: $parentNoteId, noteId: $noteId, title: $title, type: "text", content: $content}' \
    > "$payload_file"
  # NOTE: 同様に、curl --data "$payload" のようにシェル変数展開でコマンドライン
  # 引数として渡すと大きいドキュメントで "Argument list too long" になるため、
  # --data @<file> でファイルから直接読み込む。
  curl -sf -X POST -H "$auth_header" -H "Content-Type: application/json" \
    --data "@$payload_file" \
    "$TRILIUM_HTTP_URL/etapi/create-note" >/dev/null

  for label_name in "$marker_label" "docType" "topic"; do
    case "$label_name" in
      "$marker_label") label_value="1" ;;
      docType) label_value="$doc_type" ;;
      topic) label_value="$topic" ;;
    esac
    trilium_upsert_label '{"attributes": []}' "$note_id" "$label_name" "$label_value" "$auth_header" "$TRILIUM_HTTP_URL"
  done

  trilium_link_siblings "$note_id" "$topic" "$doc_type"
else
  echo "ERROR: unexpected status $get_status from Trilium existence check ($TRILIUM_HTTP_URL/etapi/notes/$note_id)" >&2
  exit 1
fi

echo "$TRILIUM_HTTP_URL/share/$note_id"
