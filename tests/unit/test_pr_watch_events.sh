#!/usr/bin/env bash

# watch-pr-events.sh のイベント出力を gh スタブで検証する。
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
SCRIPT="$ROOT_DIR/home/dot_claude/skills/pr-health-monitor/scripts/watch-pr-events.sh"
TEST_DIR=$(mktemp -d)
TEST_BIN="$TEST_DIR/bin"
STUB_DIR="$TEST_DIR/stub"
FAILED=0

trap 'rm -rf "$TEST_DIR"' EXIT
mkdir -p "$TEST_BIN" "$TEST_DIR/home"

# gh スタブ: 種類ごとの呼び出し回数 N に対し <kind>.N を返す (無ければ N 未満で最大のものを使う)。内容が FAIL なら失敗する。
cat > "$TEST_BIN/gh" <<'STUB'
#!/usr/bin/env bash
case "$1 $2" in
    "pr view") kind=view ;;
    "pr checks") kind=checks ;;
    "api graphql") kind=graphql ;;
    *) exit 1 ;;
esac
cnt_file="$STUB_DIR/$kind.count"
n=$(( $(cat "$cnt_file" 2>/dev/null || echo 0) + 1 ))
echo "$n" > "$cnt_file"
while [[ $n -ge 1 && ! -f "$STUB_DIR/$kind.$n" ]]; do n=$((n - 1)); done
[[ $n -ge 1 ]] || exit 1
content=$(cat "$STUB_DIR/$kind.$n")
if [[ "$content" == "FAIL" ]]; then
    echo "stub failure" >&2
    exit 1
fi
printf '%s\n' "$content"
STUB
chmod +x "$TEST_BIN/gh"

reset() { rm -rf "$STUB_DIR"; mkdir -p "$STUB_DIR"; }
# view N STATE MERGEABLE HEAD [ISDRAFT=false] [REVIEW_DECISION=""]
view() { jq -nc --arg s "$2" --arg m "$3" --arg h "$4" --argjson d "${5:-false}" --arg r "${6:-}" '{state:$s,mergeable:$m,headRefOid:$h,isDraft:$d,reviewDecision:$r}' > "$STUB_DIR/view.$1"; }
# checks N JSON
checks() { printf '%s\n' "$2" > "$STUB_DIR/checks.$1"; }
# graphql N REVIEWS_JSON THREADS_JSON
graphql() { jq -nc --argjson r "$2" --argjson t "$3" '{data:{repository:{pullRequest:{reviews:{nodes:$r},reviewThreads:{nodes:$t}}}}}' > "$STUB_DIR/graphql.$1"; }
init_defaults() {
    reset
    checks 1 '[{"name":"a","bucket":"pending"}]'
    graphql 1 '[]' '[]'
}

run_watch() {
    local deadline="${DEADLINE:-$(( $(date +%s) + 10800 ))}"
    HOME="$TEST_DIR/home" PATH="$TEST_BIN:$PATH" STUB_DIR="$STUB_DIR" POLL_INTERVAL=0.05 \
        READY_REMIND_INTERVAL="${READY_REMIND_INTERVAL:-600}" COPILOT_WAIT_TIMEOUT="${COPILOT_WAIT_TIMEOUT:-600}" \
        timeout 20 bash "$SCRIPT" "${ARGS_OWNER:-o}" "${ARGS_REPO:-r}" "${ARGS_PR:-1}" "$deadline" "${COPILOT_MODE:-required}" 2>/dev/null
}

check() {
    local name="$1" expected="$2" actual="$3"
    if [[ "$expected" == "$actual" ]]; then
        echo "PASS: $name"
    else
        echo "FAIL: $name"
        echo "  expected: $(printf '%s' "$expected" | tr '\n' '|')"
        echo "  actual:   $(printf '%s' "$actual" | tr '\n' '|')"
        FAILED=1
    fi
}

BOB='{"author":{"login":"bob","__typename":"User"},"state":"COMMENTED","submittedAt":"2026-01-01T00:00:00Z"}'
COPILOT='{"author":{"login":"copilot-pull-request-reviewer","__typename":"Bot"},"state":"APPROVED","submittedAt":"2026-01-01T00:00:00Z"}'

# 1. 個別チェックの成功では出力が空 (pr_closed のみ)
init_defaults
view 1 OPEN MERGEABLE h1
checks 1 '[{"name":"a","bucket":"pass"},{"name":"b","bucket":"pending"}]'
view 2 MERGED MERGEABLE h1
check "individual success is silent" "pr_closed state=MERGED" "$(run_watch)"

# 2. ci_failed は集合が変わらなければ重複しない
init_defaults
view 1 OPEN MERGEABLE h1
checks 1 '[{"name":"b","bucket":"fail"},{"name":"a","bucket":"cancel"},{"name":"c","bucket":"pass"}]'
view 4 MERGED MERGEABLE h1
check "ci_failed once per set" $'ci_failed names=a,b\npr_closed state=MERGED' "$(run_watch)"

# 3. ci_all_success は同じ head で 1 回、head が変わると再度
init_defaults
view 1 OPEN MERGEABLE h1
checks 1 '[{"name":"a","bucket":"pass"},{"name":"b","bucket":"skipping"}]'
view 3 OPEN MERGEABLE h2
view 5 MERGED MERGEABLE h2
check "ci_all_success per head" $'ci_all_success\nci_all_success\npr_closed state=MERGED' "$(run_watch)"

# 4. review_feedback: 作者自身を含む全員の review / スレッドコメントで出る
init_defaults
view 1 OPEN MERGEABLE h1
graphql 2 "[$BOB]" '[]'
graphql 3 "[$BOB]" '[{"isResolved":false,"comments":{"nodes":[{"author":{"login":"alice"}}]}}]'
graphql 4 "[$BOB]" '[{"isResolved":false,"comments":{"nodes":[{"author":{"login":"alice"}},{"author":{"login":"bob"}}]}}]'
view 5 MERGED MERGEABLE h1
check "review_feedback includes author comments" $'review_feedback unresolved=0 copilot_reviews=0\nreview_feedback unresolved=1 copilot_reviews=0\nreview_feedback unresolved=1 copilot_reviews=0\npr_closed state=MERGED' "$(run_watch)"

# 4a. 作者本人 (alice) の COMMENTED review と未解決スレッド 2 件だけでも発火する
ALICE='{"author":{"login":"alice","__typename":"User"},"state":"COMMENTED","submittedAt":"2026-01-01T00:00:00Z"}'
THR='{"isResolved":false,"comments":{"nodes":[{"author":{"login":"alice"}}]}}'
init_defaults
view 1 OPEN MERGEABLE h1
graphql 2 "[$ALICE]" "[$THR,$THR]"
view 3 MERGED MERGEABLE h1
check "author-only review fires review_feedback" $'review_feedback unresolved=2 copilot_reviews=0\npr_closed state=MERGED' "$(run_watch)"

# 4b. unresolved=0 の Copilot 承認でも出る
init_defaults
view 1 OPEN MERGEABLE h1
graphql 2 "[$COPILOT]" '[]'
view 3 MERGED MERGEABLE h1
check "copilot approval emits review_feedback" $'review_feedback unresolved=0 copilot_reviews=1\npr_closed state=MERGED' "$(run_watch)"

# 5. MERGED で pr_closed と終了コード 0
init_defaults
view 1 MERGED MERGEABLE h1
rc=0
out=$(run_watch) || rc=$?
check "pr_closed MERGED exits 0" "pr_closed state=MERGED|0" "$out|$rc"

# 6. conflict は遷移時のみ 1 回
init_defaults
view 1 OPEN MERGEABLE h1
view 2 OPEN CONFLICTING h1
view 4 MERGED CONFLICTING h1
check "conflict once on transition" $'pr_conflict_detected mergeable=CONFLICTING\npr_closed state=MERGED' "$(run_watch)"

# 6b. 開始時点で CONFLICTING なら最初のサイクルで 1 回
init_defaults
view 1 OPEN CONFLICTING h1
view 3 MERGED CONFLICTING h1
check "conflict at start" $'pr_conflict_detected mergeable=CONFLICTING\npr_closed state=MERGED' "$(run_watch)"

# 7. DEADLINE_EPOCH 超過
init_defaults
view 1 OPEN MERGEABLE h1
rc=0
out=$(DEADLINE=1 run_watch) || rc=$?
check "deadline reached" "monitor_deadline_reached|0" "$out|$rc"

# 7c. 10 回連続失敗で 5 回ごとに WARNING を再通知
init_defaults
for i in $(seq 1 10); do
    echo FAIL > "$STUB_DIR/view.$i"
    echo FAIL > "$STUB_DIR/checks.$i"
    echo FAIL > "$STUB_DIR/graphql.$i"
done
view 11 MERGED MERGEABLE h1
check "warning re-emitted every 5 failures" $'WARNING consecutive_failures=5 last_error=stub failure\nWARNING consecutive_failures=10 last_error=stub failure\npr_closed state=MERGED' "$(run_watch)"

# 6c. 一時的な UNKNOWN を挟んでも conflict は 1 回
init_defaults
view 1 OPEN CONFLICTING h1
view 2 OPEN UNKNOWN h1
view 3 OPEN CONFLICTING h1
view 5 MERGED CONFLICTING h1
check "conflict not repeated after UNKNOWN" $'pr_conflict_detected mergeable=CONFLICTING\npr_closed state=MERGED' "$(run_watch)"

# 3b. チェック 0 件でも連続 2 回空なら ci_all_success を 1 回
init_defaults
view 1 OPEN MERGEABLE h1
checks 1 '[]'
view 5 MERGED MERGEABLE h1
check "zero checks emits ci_all_success once" $'ci_all_success\npr_closed state=MERGED' "$(run_watch)"

# 8. 不正な引数は終了コード 2 で標準出力なし
init_defaults
view 1 MERGED MERGEABLE h1
for bad in "o/x:r:1" "o:r;id:1" "o:r:abc"; do
    IFS=: read -r bo br bp <<< "$bad"
    rc=0
    out=$(ARGS_OWNER="$bo" ARGS_REPO="$br" ARGS_PR="$bp" run_watch) || rc=$?
    check "invalid args ($bad) exit 2" "|2" "$out|$rc"
done

# 9. ready_eligible: 条件が揃った draft で 1 回 (CI が pending のままでも出る)。waived は既定の起点・タイムアウト (600 秒) のままでも待たずに出る
init_defaults
view 1 OPEN MERGEABLE h1 true
view 4 MERGED MERGEABLE h1 true
check "ready_eligible once (waived, CI pending)" $'ready_eligible\npr_closed state=MERGED' "$(COPILOT_MODE=waived run_watch)"

# 9a. 未解決スレッドがある間は出ず、解決後に出る
THR_RESOLVED='{"isResolved":true,"comments":{"nodes":[{"author":{"login":"alice"}}]}}'
init_defaults
view 1 OPEN MERGEABLE h1 true
graphql 1 '[]' "[$THR]"
graphql 3 '[]' "[$THR_RESOLVED]"
view 6 MERGED MERGEABLE h1 true
check "ready_eligible after threads resolved" $'review_feedback unresolved=1 copilot_reviews=0\nready_eligible\npr_closed state=MERGED' "$(COPILOT_MODE=waived run_watch)"

# 9b. required は Copilot レビュー受信後に出る
init_defaults
view 1 OPEN MERGEABLE h1 true
graphql 3 "[$COPILOT]" '[]'
view 6 MERGED MERGEABLE h1 true
check "ready_eligible waits for copilot (required)" $'review_feedback unresolved=0 copilot_reviews=1\nready_eligible\npr_closed state=MERGED' "$(COPILOT_MODE=required run_watch)"

# 9c. required で Copilot レビューが無いまま、タイムアウト前なら出ない
init_defaults
view 1 OPEN MERGEABLE h1 true
view 4 MERGED MERGEABLE h1 true
check "no ready_eligible without copilot (required)" "pr_closed state=MERGED" "$(COPILOT_MODE=required COPILOT_WAIT_TIMEOUT=600 run_watch)"

# 9d. CONFLICTING の間は出ず、解消後に出る
init_defaults
view 1 OPEN CONFLICTING h1 true
view 4 OPEN MERGEABLE h1 true
view 6 MERGED MERGEABLE h1 true
check "ready_eligible after conflict resolved" $'pr_conflict_detected mergeable=CONFLICTING\nready_eligible\npr_closed state=MERGED' "$(COPILOT_MODE=waived run_watch)"

# 9e. UNKNOWN の間は出ない
init_defaults
view 1 OPEN UNKNOWN h1 true
view 4 MERGED UNKNOWN h1 true
check "no ready_eligible while mergeable UNKNOWN" "pr_closed state=MERGED" "$(COPILOT_MODE=waived run_watch)"

# 9f. CHANGES_REQUESTED の間は出ない
init_defaults
view 1 OPEN MERGEABLE h1 true CHANGES_REQUESTED
view 4 MERGED MERGEABLE h1 true CHANGES_REQUESTED
check "no ready_eligible on CHANGES_REQUESTED" "pr_closed state=MERGED" "$(COPILOT_MODE=waived run_watch)"

# 9g. isDraft=false なら出ない
init_defaults
view 1 OPEN MERGEABLE h1 false
view 4 MERGED MERGEABLE h1 false
check "no ready_eligible when not draft" "pr_closed state=MERGED" "$(COPILOT_MODE=waived run_watch)"

# 9h. 成立が続く間は READY_REMIND_INTERVAL ごとに再出力 (秒単位のため厳密な回数は固定しない)
init_defaults
view 1 OPEN MERGEABLE h1 true
view 45 MERGED MERGEABLE h1 true
out=$(COPILOT_MODE=waived READY_REMIND_INTERVAL=1 run_watch)
check "ready_eligible re-emitted" "true" "$([[ $(grep -c '^ready_eligible$' <<<"$out") -ge 2 ]] && echo true || echo false)"

# 9i. COPILOT_MODE が不正なら終了コード 2 で標準出力なし
init_defaults
view 1 MERGED MERGEABLE h1
rc=0
out=$(COPILOT_MODE=bogus run_watch) || rc=$?
check "invalid COPILOT_MODE exit 2" "|2" "$out|$rc"

# 9j. required でも起点から COPILOT_WAIT_TIMEOUT 経過後は Copilot レビューなしで出る (起点を 100 秒前に置いて決定的にする)
init_defaults
view 1 OPEN MERGEABLE h1 true
view 4 MERGED MERGEABLE h1 true
check "ready_eligible after copilot timeout (required)" $'ready_eligible\npr_closed state=MERGED' "$(DEADLINE=$(( $(date +%s) + 10800 - 100 )) COPILOT_MODE=required COPILOT_WAIT_TIMEOUT=1 run_watch)"

# 9k. READY_REMIND_INTERVAL / COPILOT_WAIT_TIMEOUT が正の整数でなければ終了コード 2 で標準出力なし
init_defaults
view 1 MERGED MERGEABLE h1
for bad in abc 0; do
    rc=0
    out=$(READY_REMIND_INTERVAL="$bad" run_watch) || rc=$?
    check "invalid READY_REMIND_INTERVAL=$bad exit 2" "|2" "$out|$rc"
    rc=0
    out=$(COPILOT_WAIT_TIMEOUT="$bad" run_watch) || rc=$?
    check "invalid COPILOT_WAIT_TIMEOUT=$bad exit 2" "|2" "$out|$rc"
done

# 9l. gh pr checks が失敗し続けても ready_eligible は出る
init_defaults
echo FAIL > "$STUB_DIR/checks.1"
view 1 OPEN MERGEABLE h1 true
view 4 MERGED MERGEABLE h1 true
check "ready_eligible independent of gh pr checks failure" $'ready_eligible\npr_closed state=MERGED' "$(COPILOT_MODE=waived run_watch)"

exit "$FAILED"
