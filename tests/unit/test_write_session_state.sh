#!/usr/bin/env bash

# write-session-state.sh の出力・権限・異常系を gh スタブで検証する。
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
SCRIPT="$ROOT_DIR/home/bin/executable_write-session-state.sh"
TEST_DIR=$(mktemp -d)
TEST_BIN="$TEST_DIR/bin"
FAILED=0

trap 'rm -rf "$TEST_DIR"' EXIT
mkdir -p "$TEST_BIN"

# gh スタブ: 受け取った引数を記録し、STUB_URL を出力する (STUB_FAIL=1 なら何も出さず失敗する)。
cat > "$TEST_BIN/gh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" > "$STUB_ARGS"
[[ "${STUB_FAIL:-}" == "1" ]] && exit 1
printf '%s' "${STUB_URL:-}"
STUB
chmod +x "$TEST_BIN/gh"

pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; FAILED=1; }
# check NAME EXPECTED ACTUAL
check() { if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1 (expected: $2, actual: $3)"; fi; }
ARGS_NOREPO="pr view --json url -q .url"

# run_case NAME [ARGS...]: HOME を分離して実行し、終了コードを RC、標準出力を OUT に入れる。
run_case() {
    HOME="$TEST_DIR/home_$1"
    rm -rf "$HOME"
    mkdir -p "$HOME"
    shift
    STATE="$HOME/.claude/data/session-state.json"
    STUB_ARGS="$TEST_DIR/args"
    export HOME STUB_ARGS
    set +e
    OUT=$(PATH="$TEST_BIN:$PATH" bash "$SCRIPT" "$@" 2>"$TEST_DIR/stderr")
    RC=$?
    set -e
}

# 1. リポジトリ指定あり
STUB_URL="https://github.com/o/r/pull/7" CLAUDE_CODE_SESSION_ID="sess-1" run_case repo "o/r"
check "exit code with repo" 0 "$RC"
check "gh gets --repo" "pr view --repo o/r --json url -q .url" "$(cat "$STUB_ARGS")"
check "pr_url written" "https://github.com/o/r/pull/7" "$(jq -r .pr_url "$STATE")"
check "URL printed to stdout" "https://github.com/o/r/pull/7" "$OUT"
check "session_id written" "sess-1" "$(jq -r .session_id "$STATE")"
check "timestamp is a number" "number" "$(jq -r '.timestamp | type' "$STATE")"
check "state file mode" 600 "$(stat -c %a "$STATE")"
check "timestamp is recent" 1 "$(jq -r --argjson now "$(date +%s)" 'if (($now - .timestamp) | fabs) < 60 then 1 else 0 end' "$STATE")"
check "data dir mode" 700 "$(stat -c %a "$HOME/.claude/data")"

# 2. リポジトリ指定なし / 空文字は --repo を付けない
STUB_URL="https://github.com/o/r/pull/8" run_case norepo
check "no arg: exit code" 0 "$RC"
check "no arg omits --repo" "$ARGS_NOREPO" "$(cat "$STUB_ARGS")"
STUB_URL="https://github.com/o/r/pull/8" run_case emptyrepo ""
check "empty arg: exit code" 0 "$RC"
check "empty arg omits --repo" "$ARGS_NOREPO" "$(cat "$STUB_ARGS")"

# 3. session_id 未設定なら空文字
unset CLAUDE_CODE_SESSION_ID
STUB_URL="https://github.com/o/r/pull/9" run_case nosession "o/r"
check "missing session id is empty" "" "$(jq -r .session_id "$STATE")"

# 4. 空の URL はエラーで、ファイルを書かない
STUB_URL="" run_case emptyurl "o/r"
check "empty URL: exit code" 1 "$RC"
check "empty URL: no state file" "absent" "$([[ -e "$STATE" ]] && echo present || echo absent)"
check "empty URL message" 1 "$(grep -c 'empty URL' "$TEST_DIR/stderr")"

# 5. gh 失敗時 (出力なし) もファイルを書かない
STUB_FAIL=1 run_case ghfail "o/r"
check "gh failure: exit code" 1 "$RC"
check "gh failure message" 1 "$(grep -c 'gh pr view failed' "$TEST_DIR/stderr")"
check "gh failure: no state file" "absent" "$([[ -e "$STATE" ]] && echo present || echo absent)"

# 6. ~/.claude/data を作れない場合はエラー
HOME="$TEST_DIR/home_nodata"
rm -rf "$HOME"
mkdir -p "$HOME"
: > "$HOME/.claude"
export HOME
set +e
OUT=$(PATH="$TEST_BIN:$PATH" STUB_URL="https://github.com/o/r/pull/1" STUB_ARGS="$TEST_DIR/args" bash "$SCRIPT" "o/r" 2>"$TEST_DIR/stderr")
RC=$?
set -e
check "unwritable data dir: exit code" 1 "$RC"
check "unwritable data dir message" 1 "$(grep -c 'failed to prepare' "$TEST_DIR/stderr")"

exit "$FAILED"
