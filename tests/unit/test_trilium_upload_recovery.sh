#!/bin/bash
# marker のない既存ノートを保護する trilium-upload.sh のテスト。
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

# marker 付与に失敗した場合も所有権を証明できないため再実行を拒否する。
new_stub ac1
if STUB_FAIL_MARKER_POST=1 run_upload "orphan01" >"$WORK_DIR/out1" 2>"$WORK_DIR/err1"; then
  echo "❌ first run should fail when the marker POST fails"
  FAILED=1
fi
: > "$STUB_DIR/log"
if run_upload "orphan01" >"$WORK_DIR/out2" 2>"$WORK_DIR/err2"; then
  echo "❌ retry without a marker should be refused"
  FAILED=1
fi
check "retry without proof makes no writes" test ! -s "$STUB_DIR/log"

# 同じ親の属性なしノートも無関係なノートとして保護する。
new_stub collision
seed_note "foreign02" "$FOLDER_ID" "[]" "original title"
if run_upload "foreign02" >"$WORK_DIR/out_collision" 2>"$WORK_DIR/err_collision"; then
  echo "❌ unmarked note under the same parent should be refused"
  FAILED=1
fi
check "collision preserves title and content without writes" \
  test "$(jq -r .title "$STUB_DIR/notes/foreign02.json")" = "original title" -a "$(cat "$STUB_DIR/content/foreign02")" = "seeded" -a ! -s "$STUB_DIR/log"

# 継承した marker も所有権の証明にはならない。
new_stub inherited
seed_note "foreign03" "$FOLDER_ID" '[{"noteId":"folder_mytopic","type":"label","name":"triliumUploadTool","value":"1"}]' "original title"
if run_upload "foreign03" >"$WORK_DIR/out_inherited" 2>"$WORK_DIR/err_inherited"; then
  echo "❌ inherited marker should not authorize an update"
  FAILED=1
fi
check "inherited marker preserves title and content without writes" \
  test "$(jq -r .title "$STUB_DIR/notes/foreign03.json")" = "original title" -a "$(cat "$STUB_DIR/content/foreign03")" = "seeded" -a ! -s "$STUB_DIR/log"

# 自身の marker を持つノートは更新できる。
new_stub owned
seed_note "owned001" "$FOLDER_ID" '[{"noteId":"owned001","type":"label","name":"triliumUploadTool","value":"1"}]' "old title"
if run_upload "owned001" >"$WORK_DIR/out_owned" 2>"$WORK_DIR/err_owned"; then
  check "owned note is updated" test "$(jq -r .title "$STUB_DIR/notes/owned001.json")" = "new title" -a "$(cat "$STUB_DIR/content/owned001")" = "<p>stub</p>"
else
  echo "❌ owned note should be updated"
  FAILED=1
fi

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

if [ "$FAILED" -eq 0 ]; then
  echo "✅ All trilium upload recovery tests passed"
else
  echo "❌ Some trilium upload recovery tests failed"
  exit 1
fi
