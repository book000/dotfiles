#!/bin/bash
# trilium-upload.sh の復旧経路(新規作成後に marker 付与が失敗したノートの再実行)と、
# trilium_is_unmarked_upload_orphan のユニットテスト。
# curl / pandoc は stub に差し替えるため、ネットワークアクセスや実 ~/.env の読み込みは行わない。

set -euo pipefail

echo "Testing trilium-upload.sh marker recovery..."

if ! command -v jq >/dev/null 2>&1; then
  echo "⚠️ jq is not installed; skipping trilium upload recovery tests"
  exit 0
fi

FAILED=0

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
UPLOAD_SH="$REPO_DIR/home/bin/executable_trilium-upload.sh"
TRILIUM_COMMON="$REPO_DIR/home/bin/trilium-common.sh"

WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

STUB_BIN="$WORK_DIR/bin"
FAKE_HOME="$WORK_DIR/home"
mkdir -p "$STUB_BIN" "$FAKE_HOME"
cat > "$FAKE_HOME/.env" <<'EOF'
TRILIUM_HTTP_URL=http://trilium.test
TRILIUM_ETAPI_TOKEN=dummy-token
EOF

cat > "$STUB_BIN/pandoc" <<'EOF'
#!/bin/bash
# 出力ファイル(-o の次の引数)へ固定の HTML を書く。
while [ "$#" -gt 0 ]; do
  if [ "$1" = "-o" ]; then
    echo "<p>stub</p>" > "$2"
    exit 0
  fi
  shift
done
exit 1
EOF

# ETAPI を模した curl。状態は $STUB_DIR 配下のファイルに保持する。
#   notes/<id>.json : {noteId,title,parentNoteIds,attributes}
#   content/<id>    : 本文
#   log             : 変更系リクエストの記録(PATCH/PUT/ATTR_POST/CREATE)
cat > "$STUB_BIN/curl" <<'EOF'
#!/bin/bash
set -euo pipefail

method=GET
fail_on_error=0
out_file=""
write_fmt=""
data=""
url=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    -s | -G) ;;
    -sf) fail_on_error=1 ;;
    -X) method="$2"; shift ;;
    -H | --data-urlencode) shift ;;
    -o) out_file="$2"; shift ;;
    -w) write_fmt="$2"; shift ;;
    --data | --data-binary)
      data="$2"
      shift
      case "$data" in
        @*) data=$(cat "${data#@}") ;;
      esac
      ;;
    http*) url="$1" ;;
    *) echo "curl stub: unsupported argument: $1" >&2; exit 2 ;;
  esac
  shift
done

path="${url#http://trilium.test}"
status=200
body=""

case "$method $path" in
  "GET /etapi/notes")
    body='{"results": []}'
    ;;
  "GET /etapi/notes/"*)
    id="${path#/etapi/notes/}"
    if [ -f "$STUB_DIR/notes/$id.json" ]; then
      body=$(cat "$STUB_DIR/notes/$id.json")
    else
      status=404
    fi
    ;;
  "PATCH /etapi/notes/"*)
    id="${path#/etapi/notes/}"
    title=$(printf '%s' "$data" | jq -r .title)
    jq --arg t "$title" '.title = $t' "$STUB_DIR/notes/$id.json" > "$STUB_DIR/tmp.json"
    mv "$STUB_DIR/tmp.json" "$STUB_DIR/notes/$id.json"
    echo "PATCH $id" >> "$STUB_DIR/log"
    ;;
  "PUT /etapi/notes/"*"/content")
    id="${path#/etapi/notes/}"
    id="${id%/content}"
    printf '%s' "$data" > "$STUB_DIR/content/$id"
    echo "PUT $id" >> "$STUB_DIR/log"
    ;;
  "POST /etapi/create-note")
    id=$(printf '%s' "$data" | jq -r .noteId)
    printf '%s' "$data" | jq '{noteId, title, parentNoteIds: [.parentNoteId], attributes: []}' > "$STUB_DIR/notes/$id.json"
    printf '%s' "$data" | jq -r .content > "$STUB_DIR/content/$id"
    echo "CREATE $id" >> "$STUB_DIR/log"
    ;;
  "POST /etapi/attributes")
    id=$(printf '%s' "$data" | jq -r .noteId)
    name=$(printf '%s' "$data" | jq -r .name)
    if [ "$name" = "triliumUploadTool" ] && [ "${STUB_FAIL_MARKER_POST:-0}" = "1" ]; then
      status=500
    else
      jq --argjson a "$data" '.attributes += [$a]' "$STUB_DIR/notes/$id.json" > "$STUB_DIR/tmp.json"
      mv "$STUB_DIR/tmp.json" "$STUB_DIR/notes/$id.json"
      echo "ATTR_POST $id $name" >> "$STUB_DIR/log"
    fi
    ;;
  *)
    echo "curl stub: unsupported request: $method $path" >&2
    exit 2
    ;;
esac

if [ "$fail_on_error" = "1" ] && [ "$status" -ge 400 ]; then
  exit 22
fi

if [ -n "$out_file" ]; then
  printf '%s' "$body" > "$out_file"
else
  printf '%s' "$body"
fi
if [ -n "$write_fmt" ]; then
  printf '%s' "${write_fmt//%\{http_code\}/$status}"
fi
EOF
chmod +x "$STUB_BIN/pandoc" "$STUB_BIN/curl"

DOC_FILE="$WORK_DIR/doc.md"
printf '# doc\n\nbody\n' > "$DOC_FILE"

TOPIC="mytopic"
FOLDER_ID="folder_mytopic"

new_stub() {
  export STUB_DIR="$WORK_DIR/stub-$1"
  rm -rf "$STUB_DIR"
  mkdir -p "$STUB_DIR/notes" "$STUB_DIR/content"
  : > "$STUB_DIR/log"
  seed_note "$FOLDER_ID" "_share" "[]" "folder"
}

# $1=noteId $2=parentNoteId $3=attributes(JSON 配列) $4=title
seed_note() {
  jq -n --arg id "$1" --arg parent "$2" --argjson attrs "$3" --arg title "$4" \
    '{noteId: $id, title: $title, parentNoteIds: [$parent], attributes: $attrs}' \
    > "$STUB_DIR/notes/$1.json"
  echo "seeded" > "$STUB_DIR/content/$1"
}

run_upload() {
  HOME="$FAKE_HOME" PATH="$STUB_BIN:$PATH" bash "$UPLOAD_SH" "$DOC_FILE" "$1" "$TOPIC" spec "new title"
}

check() {
  local desc="$1"
  shift
  if "$@"; then
    echo "✅ $desc"
  else
    echo "❌ $desc"
    FAILED=1
  fi
}

note_attr_names() {
  jq -r '[.attributes[].name] | sort | join(",")' "$STUB_DIR/notes/$1.json"
}

# create 成功 → marker POST 失敗 → 同じ引数で再実行すると復旧できる
new_stub ac1
if STUB_FAIL_MARKER_POST=1 run_upload "orphan01" >"$WORK_DIR/out1" 2>"$WORK_DIR/err1"; then
  echo "❌ first run should fail when the marker POST fails"
  FAILED=1
else
  echo "✅ first run fails when the marker POST fails"
fi
check "orphan note exists with no attributes after the failed first run" \
  test -f "$STUB_DIR/notes/orphan01.json" -a "$(jq '.attributes | length' "$STUB_DIR/notes/orphan01.json")" = "0"
if run_upload "orphan01" >"$WORK_DIR/out2" 2>"$WORK_DIR/err2"; then
  echo "✅ retry with the same noteId succeeds"
else
  echo "❌ retry with the same noteId failed: $(cat "$WORK_DIR/err2")"
  FAILED=1
fi
check "retry leaves marker, docType and topic labels" \
  test "$(note_attr_names orphan01)" = "docType,topic,triliumUploadTool"
check "retry prints the share URL on the last line" \
  test "$(tail -n 1 "$WORK_DIR/out2")" = "http://trilium.test/share/orphan01"

# 別の親を持つ marker なしノートは拒否される
new_stub ac2
seed_note "foreign01" "some_other_parent" "[]" "unrelated"
if run_upload "foreign01" >"$WORK_DIR/out3" 2>"$WORK_DIR/err3"; then
  echo "❌ note under another parent should be refused"
  FAILED=1
else
  echo "✅ note under another parent is refused"
fi
check "refusal message names the missing marker" \
  grep -q "lacks the triliumUploadTool marker" "$WORK_DIR/err3"
check "refused note title is unchanged and nothing was written" \
  test "$(jq -r .title "$STUB_DIR/notes/foreign01.json")" = "unrelated" -a ! -s "$STUB_DIR/log"

# 正しい親でも他のラベルを持つ marker なしノートは拒否される
new_stub ac3
seed_note "labeled01" "$FOLDER_ID" '[{"noteId":"labeled01","type":"label","name":"someLabel","value":"x"}]' "labeled"
if run_upload "labeled01" >"$WORK_DIR/out4" 2>"$WORK_DIR/err4"; then
  echo "❌ labeled note without marker should be refused"
  FAILED=1
else
  echo "✅ labeled note without marker is refused"
fi
check "labeled note title is unchanged and nothing was written" \
  test "$(jq -r .title "$STUB_DIR/notes/labeled01.json")" = "labeled" -a ! -s "$STUB_DIR/log"

# trilium_is_unmarked_upload_orphan の単体判定
orphan_rc() {
  (
    # shellcheck source=/dev/null
    source "$TRILIUM_COMMON"
    trilium_is_unmarked_upload_orphan "$1" "$2"
  ) >/dev/null 2>&1
}
check "orphan check accepts matching parent and no attributes" \
  orphan_rc '{"noteId":"n1","parentNoteIds":["folder_a"],"attributes":[]}' "folder_a"
if orphan_rc '{"noteId":"n1","parentNoteIds":["other"],"attributes":[]}' "folder_a"; then
  echo "❌ orphan check should reject a different parent"
  FAILED=1
else
  echo "✅ orphan check rejects a different parent"
fi
if orphan_rc '{"noteId":"n1","parentNoteIds":["folder_a"],"attributes":[{"noteId":"n1","type":"label","name":"x","value":""}]}' "folder_a"; then
  echo "❌ orphan check should reject a note with its own attribute"
  FAILED=1
else
  echo "✅ orphan check rejects a note with its own attribute"
fi
check "orphan check ignores attributes owned by another note" \
  orphan_rc '{"noteId":"n1","parentNoteIds":["folder_a"],"attributes":[{"noteId":"folder_a","type":"label","name":"x","value":""}]}' "folder_a"
if orphan_rc 'not json' "folder_a"; then
  echo "❌ orphan check should reject invalid JSON"
  FAILED=1
else
  echo "✅ orphan check rejects invalid JSON"
fi

if [ "$FAILED" -eq 0 ]; then
  echo "✅ All trilium upload recovery tests passed"
else
  echo "❌ Some trilium upload recovery tests failed"
  exit 1
fi
