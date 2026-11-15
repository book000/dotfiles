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

# gh スタブ: 受け取った引数を記録する (STUB_FAIL=1 なら何も出さず失敗する)。
# `pr list` は STUB_LIST_JSON (未設定なら []) を、それ以外は STUB_URL を出力する。
# 実 gh と同様に、`pr view` に --repo を渡すのに PR 番号・URL・ブランチの位置引数が無い場合は失敗する。
cat > "$TEST_BIN/gh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" > "$STUB_ARGS"
if [[ "${1:-}" == "pr" && "${2:-}" == "list" ]]; then
    [[ "${STUB_FAIL:-}" == "1" ]] && exit 1
    printf '%s' "${STUB_LIST_JSON:-[]}"
    exit 0
fi
if [[ "${1:-}" == "pr" && "${2:-}" == "view" ]]; then
    has_repo=0
    has_positional=0
    shift 2
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --repo|-R) has_repo=1; shift 2 ;;
            --json|--jq|-q|--template|-t) shift 2 ;;
            -*) shift ;;
            *) has_positional=1; shift ;;
        esac
    done
    if [[ $has_repo -eq 1 && $has_positional -eq 0 ]]; then
        echo "argument required when using the --repo flag" >&2
        exit 1
    fi
fi
[[ "${STUB_FAIL:-}" == "1" ]] && exit 1
printf '%s' "${STUB_URL:-}"
STUB
chmod +x "$TEST_BIN/gh"

# git スタブ: 現在のブランチ名と origin の URL だけを返す。STUB_BRANCH が空なら detached HEAD 相当、
# STUB_ORIGIN_FAIL=1 なら origin の URL 取得に失敗する。
cat > "$TEST_BIN/git" <<'STUB'
#!/usr/bin/env bash
case "$*" in
    "branch --show-current")
        printf '%s\n' "${STUB_BRANCH-feat/x}"
        ;;
    "remote get-url origin")
        [[ "${STUB_ORIGIN_FAIL:-}" == "1" ]] && exit 1
        printf '%s\n' "${STUB_ORIGIN_URL:-git@github.com:fork/r.git}"
        ;;
    *)
        echo "unexpected git call: $*" >&2
        exit 1
        ;;
esac
STUB
chmod +x "$TEST_BIN/git"

# origin の owner の解決は実物のヘルパーを使う (スクリプトは PATH 上の名前で呼ぶ)。
cp "$ROOT_DIR/home/bin/executable_gh-pr-target-repo.sh" "$TEST_BIN/gh-pr-target-repo.sh"
chmod +x "$TEST_BIN/gh-pr-target-repo.sh"

pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; FAILED=1; }
# check NAME EXPECTED ACTUAL
check() { if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1 (expected: $2, actual: $3)"; fi; }
ARGS_NOREPO="pr view --json url -q .url"
ARGS_LIST="pr list --repo o/r --head feat/x --state all --limit 100 --json url,headRepositoryOwner"
# pr_json URL [OWNER]: `gh pr list --json url,headRepositoryOwner` の 1 件分の出力 (OWNER の既定は origin スタブの owner)
pr_json() { printf '{"url":"%s","headRepositoryOwner":{"login":"%s"}}' "$1" "${2:-fork}"; }

# run_case NAME [ARGS...]: HOME を分離して実行し、終了コードを RC、標準出力を OUT に入れる。
# KEEP_HOME=1 なら既存の HOME を作り直さない。
run_case() {
    HOME="$TEST_DIR/home_$1"
    [[ "${KEEP_HOME:-}" == "1" ]] || rm -rf "$HOME"
    mkdir -p "$HOME"
    shift
    STATE="$HOME/.claude/data/session-state-${CLAUDE_CODE_SESSION_ID:-}.json"
    STUB_ARGS="$TEST_DIR/args"
    export HOME STUB_ARGS
    set +e
    OUT=$(PATH="$TEST_BIN:$PATH" bash "$SCRIPT" "$@" 2>"$TEST_DIR/stderr")
    RC=$?
    set -e
}

# state_count: HOME 配下の session-state-*.json の数
state_count() { find "$HOME/.claude/data" -maxdepth 1 -name 'session-state-*.json' 2>/dev/null | wc -l | tr -d ' '; }

# 1. リポジトリ指定あり
STUB_LIST_JSON="[$(pr_json https://github.com/o/r/pull/7)]" CLAUDE_CODE_SESSION_ID="sess-1" run_case repo "o/r"
check "exit code with repo" 0 "$RC"
check "gh lists PRs by head branch in --repo" "$ARGS_LIST" "$(cat "$STUB_ARGS")"
check "pr_url written" "https://github.com/o/r/pull/7" "$(jq -r .pr_url "$STATE")"
check "URL printed to stdout" "https://github.com/o/r/pull/7" "$OUT"
check "session_id written" "sess-1" "$(jq -r .session_id "$STATE")"
check "timestamp is a number" "number" "$(jq -r '.timestamp | type' "$STATE")"
check "state file mode" 600 "$(stat -c %a "$STATE")"
check "timestamp is recent" 1 "$(jq -r --argjson now "$(date +%s)" 'if (($now - .timestamp) | fabs) < 60 then 1 else 0 end' "$STATE")"
check "data dir mode" 700 "$(stat -c %a "$HOME/.claude/data")"

# 1b. 同一リポジトリの PR (origin が対象リポジトリそのもの、head owner も同じ)
STUB_ORIGIN_URL="git@github.com:o/r.git" STUB_LIST_JSON="[$(pr_json https://github.com/o/r/pull/20 o)]" CLAUDE_CODE_SESSION_ID="sess-1" run_case samerepo "o/r"
check "same-repo PR: exit code" 0 "$RC"
check "same-repo PR: URL printed" "https://github.com/o/r/pull/20" "$OUT"
check "same-repo PR: pr_url written" "https://github.com/o/r/pull/20" "$(jq -r .pr_url "$STATE")"

# 1c. fork の PR (origin は fork、head owner も fork)
STUB_ORIGIN_URL="git@github.com:fork/r.git" STUB_LIST_JSON="[$(pr_json https://github.com/o/r/pull/21 fork)]" CLAUDE_CODE_SESSION_ID="sess-1" run_case forkpr "o/r"
check "fork PR: exit code" 0 "$RC"
check "fork PR: URL printed" "https://github.com/o/r/pull/21" "$OUT"
check "fork PR: pr_url written" "https://github.com/o/r/pull/21" "$(jq -r .pr_url "$STATE")"

# 1d. 同名ブランチの PR が複数ある場合は、head owner が origin の owner と一致する最新の PR を選ぶ
MULTI="[$(pr_json https://github.com/o/r/pull/32 other),$(pr_json https://github.com/o/r/pull/31 fork),$(pr_json https://github.com/o/r/pull/30 fork)]"
STUB_LIST_JSON="$MULTI" CLAUDE_CODE_SESSION_ID="sess-1" run_case multi "o/r"
check "multiple PRs: exit code" 0 "$RC"
check "multiple PRs: latest PR of the origin owner" "https://github.com/o/r/pull/31" "$OUT"

# 1e. head owner が一致する PR が無い場合は空 URL のエラーで、ファイルを書かない
STUB_LIST_JSON="[$(pr_json https://github.com/o/r/pull/33 other)]" CLAUDE_CODE_SESSION_ID="sess-1" run_case nomatch "o/r"
check "no matching PR: exit code" 1 "$RC"
check "no matching PR message" "ERROR: PR resolution returned an empty URL, not writing session state" "$(cat "$TEST_DIR/stderr")"
check "no matching PR: no state file" 0 "$(state_count)"
STUB_LIST_JSON="[]" CLAUDE_CODE_SESSION_ID="sess-1" run_case nopr "o/r"
check "no PR at all: exit code" 1 "$RC"
check "no PR at all: no state file" 0 "$(state_count)"

# 2. リポジトリ指定なし / 空文字は --repo を付けない
STUB_URL="https://github.com/o/r/pull/8" run_case norepo
check "no arg: exit code" 0 "$RC"
check "no arg omits --repo" "$ARGS_NOREPO" "$(cat "$STUB_ARGS")"
STUB_URL="https://github.com/o/r/pull/8" run_case emptyrepo ""
check "empty arg: exit code" 0 "$RC"
check "empty arg omits --repo" "$ARGS_NOREPO" "$(cat "$STUB_ARGS")"

# 2b. ブランチ名を得られない (detached HEAD) 場合はエラーで、gh を呼ばずファイルも書かない
rm -f "$TEST_DIR/args"
STUB_BRANCH="" STUB_LIST_JSON="[$(pr_json https://github.com/o/r/pull/8)]" CLAUDE_CODE_SESSION_ID="sess-1" run_case detached "o/r"
check "detached HEAD: exit code" 1 "$RC"
check "detached HEAD message" "ERROR: cannot determine the current branch (detached HEAD?)" "$(cat "$TEST_DIR/stderr")"
check "detached HEAD: gh not called" "absent" "$([[ -e "$TEST_DIR/args" ]] && echo present || echo absent)"
check "detached HEAD: no state file" 0 "$(state_count)"

# 2c. origin の owner を解決できない場合はエラーで、gh を呼ばずファイルも書かない
rm -f "$TEST_DIR/args"
STUB_ORIGIN_FAIL=1 STUB_LIST_JSON="[$(pr_json https://github.com/o/r/pull/8)]" CLAUDE_CODE_SESSION_ID="sess-1" run_case noorigin "o/r"
check "no origin: exit code" 1 "$RC"
check "no origin message" 1 "$(grep -c 'ERROR: cannot resolve the owner of origin' "$TEST_DIR/stderr")"
check "no origin: gh not called" "absent" "$([[ -e "$TEST_DIR/args" ]] && echo present || echo absent)"
check "no origin: no state file" 0 "$(state_count)"

# 3. 別セッションの state を上書きしない
STUB_LIST_JSON="[$(pr_json https://github.com/o/r/pull/10)]" CLAUDE_CODE_SESSION_ID="sess-1" run_case shared "o/r"
STUB_LIST_JSON="[$(pr_json https://github.com/o/r/pull/11)]" CLAUDE_CODE_SESSION_ID="sess-2" KEEP_HOME=1 run_case shared "o/r"
check "second session: exit code" 0 "$RC"
check "first session state is kept" "https://github.com/o/r/pull/10" "$(jq -r .pr_url "$HOME/.claude/data/session-state-sess-1.json")"
check "second session state is written" "https://github.com/o/r/pull/11" "$(jq -r .pr_url "$HOME/.claude/data/session-state-sess-2.json")"

# 4. session id が未設定または不正なら state を書かず、URL は出力して成功する
unset CLAUDE_CODE_SESSION_ID
STUB_LIST_JSON="[$(pr_json https://github.com/o/r/pull/9)]" run_case nosession "o/r"
check "missing session id: exit code" 0 "$RC"
check "missing session id: URL printed" "https://github.com/o/r/pull/9" "$OUT"
check "missing session id: no state file" 0 "$(state_count)"
check "missing session id: warning" 1 "$(grep -c "WARNING: CLAUDE_CODE_SESSION_ID is empty or contains invalid characters (got: '')" "$TEST_DIR/stderr")"
STUB_LIST_JSON="[$(pr_json https://github.com/o/r/pull/9)]" CLAUDE_CODE_SESSION_ID="../x" run_case badsession "o/r"
check "invalid session id: exit code" 0 "$RC"
check "invalid session id: URL printed" "https://github.com/o/r/pull/9" "$OUT"
check "invalid session id: no state file" 0 "$(state_count)"
check "invalid session id: nothing escapes data dir" "absent" "$([[ -e "$HOME/.claude/x.json" ]] && echo present || echo absent)"
check "invalid session id: warning" 1 "$(grep -c "WARNING: CLAUDE_CODE_SESSION_ID is empty or contains invalid characters (got: '../x')" "$TEST_DIR/stderr")"

# 5. 24 時間より古い state だけが書き込み時に削除される
mkdir -p "$TEST_DIR/home_cleanup/.claude/data"
echo '{}' > "$TEST_DIR/home_cleanup/.claude/data/session-state-old.json"
touch -d '2 days ago' "$TEST_DIR/home_cleanup/.claude/data/session-state-old.json"
echo '{}' > "$TEST_DIR/home_cleanup/.claude/data/session-state-fresh.json"
STUB_LIST_JSON="[$(pr_json https://github.com/o/r/pull/12)]" CLAUDE_CODE_SESSION_ID="sess-3" KEEP_HOME=1 run_case cleanup "o/r"
check "cleanup: exit code" 0 "$RC"
check "cleanup: stale state removed" "absent" "$([[ -e "$HOME/.claude/data/session-state-old.json" ]] && echo present || echo absent)"
check "cleanup: fresh state kept" "present" "$([[ -e "$HOME/.claude/data/session-state-fresh.json" ]] && echo present || echo absent)"
check "cleanup: own state written" "present" "$([[ -e "$HOME/.claude/data/session-state-sess-3.json" ]] && echo present || echo absent)"

# 6. 空の URL はエラーで、ファイルを書かない (session id の有無に依らない)
STUB_URL="" CLAUDE_CODE_SESSION_ID="sess-1" run_case emptyurl
check "empty URL: exit code" 1 "$RC"
check "empty URL: no state file" 0 "$(state_count)"
check "empty URL message" 1 "$(grep -c 'empty URL' "$TEST_DIR/stderr")"

STUB_URL="" run_case emptyurl_nosession
check "empty URL without session id: exit code" 1 "$RC"

# 7. gh 失敗時 (出力なし) もファイルを書かない
STUB_FAIL=1 CLAUDE_CODE_SESSION_ID="sess-1" run_case ghfail "o/r"
check "gh failure: exit code" 1 "$RC"
check "gh failure message" 1 "$(grep -c 'gh pr list failed' "$TEST_DIR/stderr")"
check "gh failure: no state file" 0 "$(state_count)"
STUB_FAIL=1 CLAUDE_CODE_SESSION_ID="sess-1" run_case ghfail_norepo
check "gh failure without repo: exit code" 1 "$RC"
check "gh failure without repo message" 1 "$(grep -c 'gh pr view failed' "$TEST_DIR/stderr")"
check "gh failure without repo: no state file" 0 "$(state_count)"

# 8. ~/.claude/data を作れない場合はエラー
HOME="$TEST_DIR/home_nodata"
rm -rf "$HOME"
mkdir -p "$HOME"
: > "$HOME/.claude"
export HOME
set +e
OUT=$(PATH="$TEST_BIN:$PATH" STUB_LIST_JSON="[$(pr_json https://github.com/o/r/pull/1)]" STUB_ARGS="$TEST_DIR/args" bash "$SCRIPT" "o/r" 2>"$TEST_DIR/stderr")
RC=$?
set -e
check "unwritable data dir: exit code" 1 "$RC"
check "unwritable data dir message" 1 "$(grep -c 'failed to prepare' "$TEST_DIR/stderr")"

exit "$FAILED"
