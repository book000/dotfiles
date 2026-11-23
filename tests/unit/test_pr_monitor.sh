#!/usr/bin/env bash

# PR monitor の durable state、lease、observer 境界を GitHub API stub で検証する。
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
STATE_SCRIPT="$ROOT_DIR/home/dot_agents/skills/pr-health-monitor/scripts/executable_pr-monitor-state.sh"
WATCH_SCRIPT="$ROOT_DIR/home/dot_agents/skills/pr-health-monitor/scripts/executable_watch-pr.sh"
DISPATCH_SCRIPT="$ROOT_DIR/home/dot_agents/skills/pr-health-monitor/scripts/executable_pr-monitor-dispatch.sh"
PANE_STATE_HOOK="$ROOT_DIR/home/dot_codex/hooks/executable_pr-monitor-pane-state.sh"
COPILOT_SCRIPT="$ROOT_DIR/home/dot_agents/skills/pr-health-monitor/scripts/executable_wait-for-copilot-review.sh"
RESOLVE_PANE_SCRIPT="$ROOT_DIR/home/dot_agents/skills/pr-health-monitor/scripts/executable_resolve-tmux-pane.sh"
TEST_DIR=$(mktemp -d)
TEST_HOME="$TEST_DIR/home"
TEST_BIN="$TEST_DIR/bin"
PR_URL="https://github.com/example/repo/pull/42"
SLEEP_PID=""

stop_tmux_children() {
    local _window_id child_pid

    [[ -f "$TEST_DIR/tmux-children" ]] || return 0
    while read -r _window_id child_pid; do
        [[ "$child_pid" =~ ^[0-9]+$ ]] || continue
        kill "$child_pid" 2>/dev/null || true
        for _ in {1..40}; do
            ! kill -0 "$child_pid" 2>/dev/null && break
            sleep 0.05
        done
    done < "$TEST_DIR/tmux-children"
    rm -f "$TEST_DIR/tmux-children"
}

stop_supervisor_watcher() {
    local watcher_pid

    watcher_pid="$1"
    kill "$watcher_pid" 2>/dev/null || true
    for _ in {1..40}; do
        ! kill -0 "$watcher_pid" 2>/dev/null && break
        sleep 0.05
    done
    if [[ -f "$TEST_DIR/tmux-children" ]]; then
        while read -r _window_id child_pid; do
            [[ "$child_pid" =~ ^[0-9]+$ ]] || continue
            kill -KILL "$child_pid" 2>/dev/null || true
        done < "$TEST_DIR/tmux-children"
        rm -f "$TEST_DIR/tmux-children"
    fi
}

cleanup() {
    stop_tmux_children
    if [[ -n "$SLEEP_PID" ]]; then
        kill "$SLEEP_PID" 2>/dev/null || true
        wait "$SLEEP_PID" 2>/dev/null || true
    fi
    rm -rf "$TEST_DIR"
}
trap cleanup EXIT

mkdir -p "$TEST_HOME" "$TEST_BIN"
mkdir -p "$TEST_HOME/.agents/skills/pr-health-monitor/scripts"
ln -s "$STATE_SCRIPT" "$TEST_HOME/.agents/skills/pr-health-monitor/scripts/pr-monitor-state.sh"
export HOME="$TEST_HOME"
export XDG_STATE_HOME="$TEST_DIR/state"
export PATH="$TEST_BIN:$PATH"
export STATE_SCRIPT WATCH_SCRIPT

cat > "$TEST_BIN/tmux" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$1" == "display-message" ]]; then
    if [[ -n "${TMUX_RESOLVER_TEST_CASE:-}" ]]; then
        pane=""
        previous=""
        for argument in "$@"; do
            if [[ "$previous" == "-t" ]]; then
                pane="$argument"
                break
            fi
            previous="$argument"
        done
        if [[ "${TMUX_RESOLVER_REVALIDATION_FAILURE:-0}" == "1" && -n "$pane" ]]; then
            exit 1
        fi
        while IFS=$'\t' read -r session_id window_id pane_id pane_pid; do
            if [[ "$pane_id" == "$pane" ]]; then
                printf '%s\t%s\t%s\t%s\n' "$session_id" "$window_id" "$pane_id" "$pane_pid"
                exit 0
            fi
        done <<< "${TMUX_RESOLVER_PANES:-}"
        exit 1
    fi
    if [[ "${TMUX_STUB_MODE:-}" == "ready-then-exit" && "${4:-}" == "@101" ]]; then
        : > "$TEST_DIR/first-window-readiness-probe"
        watcher_pid=$("$STATE_SCRIPT" show --pr-url "$TMUX_READY_EXIT_PR_URL" | jq -r '.watcher.pid // empty')
        if [[ "$watcher_pid" =~ ^[0-9]+$ ]]; then
            kill "$watcher_pid" 2>/dev/null || true
        fi
        state_id=$("$STATE_SCRIPT" id --pr-url "$TMUX_READY_EXIT_PR_URL")
        for _ in {1..100}; do
            if [[ ! -d "$XDG_STATE_HOME/codex-pr-monitor/${state_id}.watch.lock" ]]; then
                : > "$TEST_DIR/ready-then-exit-recorded"
                break
            fi
            sleep 0.01
        done
    fi
    if [[ "${4:-}" =~ ^@[0-9]+$ ]]; then
        printf '%s\n' "$4"
    else
        printf '%%77\n'
    fi
    exit 0
fi
if [[ "$1" == "list-panes" && -n "${TMUX_RESOLVER_TEST_CASE:-}" ]]; then
    if [[ "${TMUX_RESOLVER_TEST_CASE}" == "operation-failure" ]]; then
        echo "tmux: connection refused" >&2
        exit 1
    fi
    printf '%s\n' "${TMUX_RESOLVER_PANES:-}"
    exit 0
fi
if [[ "$1" == "send-keys" ]]; then
    printf '%s\n' "$*" >> "$TEST_DIR/tmux.log"
    exit 0
fi
if [[ "$1" == "new-window" ]]; then
    printf '%s\n' "$*" >> "$TEST_DIR/tmux.log"
    case "${TMUX_STUB_MODE:-immediate-exit}" in
        ready)
            command="${!#}"
            bash -c "$command" > "$TEST_DIR/tmux-child.log" 2>&1 &
            printf '@101 %s\n' "$!" >> "$TEST_DIR/tmux-children"
            ;;
        ready-then-exit)
            command="${!#}"
            bash -c "$command" > "$TEST_DIR/tmux-child.log" 2>&1 &
            child_pid=$!
            printf '@101 %s\n' "$child_pid" >> "$TEST_DIR/tmux-children"
            ;;
        immediate-exit)
            command="${!#}"
            GH_STUB_FAILURE=1 PR_MONITOR_INTERVAL=0 PR_MONITOR_MAX_POLLS=1 bash -c "$command" > "$TEST_DIR/tmux-child.log" 2>&1
            ;;
        handoff)
            command="${!#}"
            GH_STUB_FAILURE=1 PR_MONITOR_INTERVAL=0 PR_MONITOR_MAX_POLLS=1 bash -c "$command" > "$TEST_DIR/tmux-child.log" 2>&1
            ;;
        simultaneous)
            command="${!#}"
            mkdir -p "$TEST_DIR/tmux-simultaneous"
            : > "$TEST_DIR/tmux-simultaneous/$BASHPID"
            for _ in {1..100}; do
                [[ "$(find "$TEST_DIR/tmux-simultaneous" -mindepth 1 -maxdepth 1 -type f | wc -l | tr -d ' ')" -ge 2 ]] && break
                sleep 0.01
            done
            exec 9>"$TEST_DIR/tmux-simultaneous.lock"
            flock 9
            launch_count=$(cat "$TEST_DIR/tmux-simultaneous-count" 2>/dev/null || printf '0')
            launch_count=$((launch_count + 1))
            printf '%s\n' "$launch_count" > "$TEST_DIR/tmux-simultaneous-count"
            flock -u 9
            if [[ "$launch_count" -eq 1 ]]; then
                bash -c "$command" > "$TEST_DIR/tmux-child.log" 2>&1 &
                printf '@101 %s\n' "$!" >> "$TEST_DIR/tmux-children"
            else
                bash -c 'exit 0' > "$TEST_DIR/tmux-child-exit.log" 2>&1
            fi
            ;;
        fail)
            exit 1
            ;;
        *)
            exit 1
            ;;
    esac
    printf '%s\n' "${TMUX_STUB_WINDOW_OUTPUT:-@101}"
    exit 0
fi
if [[ "$1" == "kill-window" ]]; then
    printf '%s\n' "$*" >> "$TEST_DIR/tmux.log"
    window_id="${@: -1}"
    if [[ -f "$TEST_DIR/tmux-children" ]]; then
        while read -r child_window child_pid; do
            if [[ "$child_window" == "$window_id" ]]; then
                kill "$child_pid" 2>/dev/null || true
            fi
        done < "$TEST_DIR/tmux-children"
    fi
    if [[ "${TMUX_STUB_MODE:-}" == "handoff" ]]; then
        env GH_STUB_FAILURE=0 GH_STUB_OPEN=1 PR_MONITOR_INTERVAL=1 "$WATCH_SCRIPT" watch --pr-url "$TMUX_HANDOFF_PR_URL" > "$TEST_DIR/tmux-successor.log" 2>&1 &
        printf '@202 %s\n' "$!" >> "$TEST_DIR/tmux-children"
        for _ in {1..20}; do
            "$STATE_SCRIPT" show --pr-url "$TMUX_HANDOFF_PR_URL" | jq -e '.watcher.pid != null and .watcher.last_error == null' >/dev/null && break
            sleep 0.05
        done
    fi
    exit 0
fi
exit 1
EOF
chmod +x "$TEST_BIN/tmux"

cat > "$TEST_BIN/ps" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${PR_MONITOR_TEST_PROCESS_IDENTITY:-0}" == "1" && "$1" == "-p" && "${2:-}" =~ ^[0-9]+$ ]]; then
    printf 'synthetic-start-%s\n' "$2"
    exit 0
fi
if [[ "${TMUX_RESOLVER_TEST_CASE:-}" != "" && "$1" == "-o" && "${2:-}" == "ppid=" && "${3:-}" == "-p" && "${4:-}" =~ ^[0-9]+$ ]]; then
    if [[ "${TMUX_RESOLVER_TEST_CASE}" == "ps-operation-failure" ]]; then
        echo "ps: permission denied" >&2
        exit 1
    fi
    case "${TMUX_RESOLVER_TEST_CASE}" in
        unique|direct-valid|direct-stale|revalidation-failure)
            if [[ "$4" == "4242" ]]; then
                printf '1\n'
            else
                printf '4242\n'
            fi
            ;;
        unrelated|operation-failure)
            if [[ "$4" == "9999" ]]; then
                printf '1\n'
            else
                printf '9999\n'
            fi
            ;;
        ambiguous)
            case "$4" in
                4242) printf '4243\n' ;;
                4243) printf '1\n' ;;
                *) printf '4242\n' ;;
            esac
            ;;
        *) exit 1 ;;
    esac
    exit 0
fi
exec /usr/bin/ps "$@"
EOF
chmod +x "$TEST_BIN/ps"

cat > "$TEST_BIN/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${GH_STUB_FAILURE:-0}" == "1" ]]; then
    exit 1
fi

case "$1 $2" in
    "pr view")
        if [[ "${GH_STUB_OPEN:-0}" == "1" ]]; then
            printf '{"state":"OPEN","mergeable":"MERGEABLE","mergeStateStatus":"CLEAN","url":"https://github.com/example/repo/pull/%s"}\n' "$3"
        else
            printf '{"state":"MERGED","mergeable":"MERGEABLE","mergeStateStatus":"CLEAN","url":"https://github.com/example/repo/pull/%s"}\n' "$3"
        fi
        ;;
    "pr checks")
        if [[ -n "${GH_STUB_CI_FAILURE_FILE:-}" && -f "$GH_STUB_CI_FAILURE_FILE" ]]; then
            exit 1
        fi
        if [[ "${GH_STUB_CHECKS_PASS:-0}" == "1" ]]; then
            printf '%s\n' '[{"name":"unit","bucket":"pass","link":"https://github.com/example/repo/actions/runs/123"}]'
            if [[ -n "${GH_STUB_CI_OBSERVED_FILE:-}" ]]; then
                : > "$GH_STUB_CI_OBSERVED_FILE"
            fi
            exit 0
        fi
        printf '%s\n' '[{"name":"unit","bucket":"fail","link":"https://github.com/example/repo/actions/runs/123"}]'
        if [[ -n "${GH_STUB_CI_OBSERVED_FILE:-}" ]]; then
            : > "$GH_STUB_CI_OBSERVED_FILE"
        fi
        exit 1
        ;;
    "api graphql")
        printf '{"data":{"repository":{"pullRequest":{"comments":{"totalCount":%s},"reviews":{"totalCount":%s},"reviewThreads":{"nodes":[{"comments":{"totalCount":%s}}],"pageInfo":{"hasNextPage":false,"endCursor":null}}}}}}\n' \
            "${GH_STUB_CONVERSATION_COMMENTS:-0}" "${GH_STUB_REVIEWS:-0}" "${GH_STUB_REVIEW_COMMENTS:-0}"
        ;;
    *) exit 1 ;;
esac
EOF
chmod +x "$TEST_BIN/gh"

expect_failure() {
    if "$@" >/dev/null 2>&1; then
        echo "❌ Expected failure: $*" >&2
        exit 1
    fi
}

process_identity() {
    local pid="$1" started

    started=$(LC_ALL=C ps -p "$pid" -o lstart= 2>/dev/null | sed -E 's/^[[:space:]]+//; s/[[:space:]]+/ /g' || true)
    if [[ -n "$started" ]]; then
        printf 'ps-lstart:%s\n' "$started"
        return 0
    fi
    started=$(LC_ALL=C ps -p "$pid" -o start= 2>/dev/null | sed -E 's/^[[:space:]]+//; s/[[:space:]]+/ /g' || true)
    if [[ -n "$started" ]]; then
        printf 'ps-start:%s\n' "$started"
        return 0
    fi
    awk '{print "proc-start:" $22}' "/proc/$pid/stat" 2>/dev/null
}

echo "Testing fail-closed tmux pane resolution without TMUX_PANE..."
RESOLVER_PANES=$'session-1\t@1\t%77\t4242'
if ! RESOLVED_PANE=$(env -u TMUX_PANE TMUX_RESOLVER_TEST_CASE=unique TMUX_RESOLVER_PANES="$RESOLVER_PANES" "$RESOLVE_PANE_SCRIPT"); then
    echo "❌ A unique ancestor pane was not resolved" >&2
    exit 1
fi
if [[ "$RESOLVED_PANE" != "%77" ]]; then
    echo "❌ Resolver returned an unexpected unique pane: $RESOLVED_PANE" >&2
    exit 1
fi
if ! RESOLVED_PANE=$(TMUX_PANE=%77 TMUX_RESOLVER_TEST_CASE=direct-valid TMUX_RESOLVER_PANES="$RESOLVER_PANES" "$RESOLVE_PANE_SCRIPT"); then
    echo "❌ A valid direct TMUX_PANE was not resolved" >&2
    exit 1
fi
if [[ "$RESOLVED_PANE" != "%77" ]]; then
    echo "❌ Resolver changed a valid direct pane: $RESOLVED_PANE" >&2
    exit 1
fi
if UNEXPECTED_OUTPUT=$(env -u TMUX_PANE TMUX_RESOLVER_TEST_CASE=unrelated TMUX_RESOLVER_PANES="$RESOLVER_PANES" "$RESOLVE_PANE_SCRIPT" 2>&1); then
    echo "❌ Resolver accepted an unrelated pane: $UNEXPECTED_OUTPUT" >&2
    exit 1
fi
if [[ -n "$UNEXPECTED_OUTPUT" ]]; then
    echo "❌ Resolver emitted output for an unrelated pane: $UNEXPECTED_OUTPUT" >&2
    exit 1
fi
AMBIGUOUS_PANES=$'session-1\t@1\t%77\t4242\nsession-1\t@2\t%78\t4243'
if UNEXPECTED_OUTPUT=$(env -u TMUX_PANE TMUX_RESOLVER_TEST_CASE=ambiguous TMUX_RESOLVER_PANES="$AMBIGUOUS_PANES" "$RESOLVE_PANE_SCRIPT" 2>&1); then
    echo "❌ Resolver accepted ambiguous ancestor panes: $UNEXPECTED_OUTPUT" >&2
    exit 1
fi
if [[ -n "$UNEXPECTED_OUTPUT" ]]; then
    echo "❌ Resolver emitted output for ambiguous panes: $UNEXPECTED_OUTPUT" >&2
    exit 1
fi
if UNEXPECTED_OUTPUT=$(TMUX_PANE=%999 TMUX_RESOLVER_TEST_CASE=direct-stale TMUX_RESOLVER_PANES='' "$RESOLVE_PANE_SCRIPT" 2>&1); then
    echo "❌ Resolver accepted a stale direct TMUX_PANE: $UNEXPECTED_OUTPUT" >&2
    exit 1
fi
if [[ -n "$UNEXPECTED_OUTPUT" ]]; then
    echo "❌ Resolver emitted output for a stale direct TMUX_PANE: $UNEXPECTED_OUTPUT" >&2
    exit 1
fi
if ! RESOLVED_PANE=$(TMUX_PANE=%999 TMUX_RESOLVER_TEST_CASE=direct-stale TMUX_RESOLVER_PANES="$RESOLVER_PANES" "$RESOLVE_PANE_SCRIPT"); then
    echo "❌ Resolver did not recover from a stale direct TMUX_PANE" >&2
    exit 1
fi
if [[ "$RESOLVED_PANE" != "%77" ]]; then
    echo "❌ Resolver returned an unexpected stale-direct recovery pane: $RESOLVED_PANE" >&2
    exit 1
fi
if UNEXPECTED_OUTPUT=$(env -u TMUX_PANE TMUX_RESOLVER_TEST_CASE=revalidation-failure TMUX_RESOLVER_PANES="$RESOLVER_PANES" TMUX_RESOLVER_REVALIDATION_FAILURE=1 "$RESOLVE_PANE_SCRIPT" 2>&1); then
    echo "❌ Resolver accepted a pane after failed revalidation: $UNEXPECTED_OUTPUT" >&2
    exit 1
fi
if [[ "$UNEXPECTED_OUTPUT" != *"Error: Unable to validate tmux pane."* ]]; then
    echo "❌ Resolver omitted revalidation failure evidence: $UNEXPECTED_OUTPUT" >&2
    exit 1
fi
if UNEXPECTED_OUTPUT=$(env -u TMUX_PANE TMUX_RESOLVER_TEST_CASE=operation-failure TMUX_RESOLVER_PANES="$RESOLVER_PANES" "$RESOLVE_PANE_SCRIPT" 2>&1); then
    echo "❌ Resolver accepted an unavailable tmux server: $UNEXPECTED_OUTPUT" >&2
    exit 1
fi
if [[ "$UNEXPECTED_OUTPUT" != *"tmux: connection refused"* || "$UNEXPECTED_OUTPUT" != *"Error: Unable to list tmux panes."* ]]; then
    echo "❌ Resolver omitted tmux failure evidence: $UNEXPECTED_OUTPUT" >&2
    exit 1
fi
if UNEXPECTED_OUTPUT=$(env -u TMUX_PANE TMUX_RESOLVER_TEST_CASE=ps-operation-failure "$RESOLVE_PANE_SCRIPT" 2>&1); then
    echo "❌ Resolver accepted an unavailable process tree: $UNEXPECTED_OUTPUT" >&2
    exit 1
fi
if [[ "$UNEXPECTED_OUTPUT" != *"ps: permission denied"* || "$UNEXPECTED_OUTPUT" != *"Error: Unable to inspect the tmux process tree."* ]]; then
    echo "❌ Resolver omitted process-tree failure evidence: $UNEXPECTED_OUTPUT" >&2
    exit 1
fi

echo "Testing absolute state directory and collision-resistant keys..."
expect_failure env XDG_STATE_HOME=relative HOME="$TEST_HOME" "$STATE_SCRIPT" init --pr-url "$PR_URL"
ID_DASH=$("$STATE_SCRIPT" id --pr-url "https://github.com/example/repo-a/pull/42")
ID_DOT=$("$STATE_SCRIPT" id --pr-url "https://github.com/example/repo.a/pull/42")
if [[ "$ID_DASH" == "$ID_DOT" || ! "$ID_DASH" =~ ^[a-f0-9]{64}$ ]]; then
    echo "❌ Canonical PR URLs do not have collision-resistant state keys" >&2
    exit 1
fi

echo "Testing state URL verification and stale/live lock recovery..."
"$STATE_SCRIPT" init --pr-url "$PR_URL" >/dev/null

echo "Testing tmux monitor readiness and recovery..."
SECOND_PR_URL="https://github.com/example/repo/pull/43"
expect_failure "$STATE_SCRIPT" register-pane --pr-url "$SECOND_PR_URL" --pane %77 --nonce 0123456789abcdef
"$STATE_SCRIPT" init --pr-url "$SECOND_PR_URL" >/dev/null
"$STATE_SCRIPT" register-pane --pr-url "$SECOND_PR_URL" --pane %77 --nonce 0123456789abcdef >/dev/null
export PR_MONITOR_TEST_PROCESS_IDENTITY=1
if ! SECOND_START_OUTPUT=$(env TMUX_STUB_MODE=ready GH_STUB_OPEN=1 GH_STUB_CHECKS_PASS=1 GH_STUB_CI_OBSERVED_FILE="$TEST_DIR/ci-observed" GH_STUB_CI_FAILURE_FILE="$TEST_DIR/ci-observation-failure" PR_MONITOR_INTERVAL=1 PR_MONITOR_START_READY_ATTEMPTS=100 TEST_DIR="$TEST_DIR" "$WATCH_SCRIPT" start --pr-url "$SECOND_PR_URL" 2>&1); then
    cat "$TEST_DIR/tmux-child.log" >&2
    cat "$TEST_DIR/tmux.log" >&2
    "$STATE_SCRIPT" show --pr-url "$SECOND_PR_URL" >&2 || true
    cat "$XDG_STATE_HOME/codex-pr-monitor/$($STATE_SCRIPT id --pr-url "$SECOND_PR_URL").watch.lock/owner.json" >&2 || true
    echo "❌ Monitor start failed before watcher readiness" >&2
    exit 1
fi
if [[ "$SECOND_START_OUTPUT" != "started $SECOND_PR_URL codex-pr-monitor-"* ]] \
    || ! "$STATE_SCRIPT" show --pr-url "$SECOND_PR_URL" | jq -e '.runtime.pane == "%77" and .runtime.nonce == "0123456789abcdef"' >/dev/null \
    || ! "$STATE_SCRIPT" show --pr-url "$SECOND_PR_URL" | jq -e '.watcher.pid != null and .watcher.last_error == null' >/dev/null \
    || ! grep -Fq "new-window -d -P -F #{window_id} -n codex-pr-monitor-" "$TEST_DIR/tmux.log"; then
    echo "❌ Monitor start did not wait for a live watcher and matching state" >&2
    exit 1
fi
SECOND_OWNER_FILE="$XDG_STATE_HOME/codex-pr-monitor/$($STATE_SCRIPT id --pr-url "$SECOND_PR_URL").watch.lock/owner.json"
SECOND_OWNER_PID=$(jq -r '.pid // empty' "$SECOND_OWNER_FILE")
SECOND_OWNER_IDENTITY=$(jq -r '.process_identity // empty' "$SECOND_OWNER_FILE")
if [[ ! "$SECOND_OWNER_PID" =~ ^[0-9]+$ ]] \
    || [[ -z "$SECOND_OWNER_IDENTITY" ]] \
    || [[ "$(process_identity "$SECOND_OWNER_PID")" != "$SECOND_OWNER_IDENTITY" ]]; then
    cat "$SECOND_OWNER_FILE" >&2
    echo "❌ Ready watcher lock PID and process identity do not describe the same process" >&2
    exit 1
fi
SECOND_WATCHER_PID=$("$STATE_SCRIPT" show --pr-url "$SECOND_PR_URL" | jq -r '.watcher.pid')
for _ in {1..20}; do
    [[ -f "$TEST_DIR/ci-observed" ]] \
        && "$STATE_SCRIPT" show --pr-url "$SECOND_PR_URL" | jq -e '.observed.ci == "ok" and .events.ci_failure == null' >/dev/null \
        && break
    sleep 0.05
done
if [[ ! -f "$TEST_DIR/ci-observed" ]] \
    || ! "$STATE_SCRIPT" show --pr-url "$SECOND_PR_URL" | jq -e '.observed.ci == "ok" and .events.ci_failure == null' >/dev/null; then
    echo "❌ Ready watcher did not complete its initial observation" >&2
    exit 1
fi
: > "$TEST_DIR/ci-observation-failure"
for _ in {1..20}; do
    "$STATE_SCRIPT" show --pr-url "$SECOND_PR_URL" | jq -e --argjson pid "$SECOND_WATCHER_PID" '.watcher.pid == $pid and .watcher.failures >= 1 and .watcher.last_error == null' >/dev/null && break
    sleep 0.05
done
if ! "$STATE_SCRIPT" show --pr-url "$SECOND_PR_URL" | jq -e --argjson pid "$SECOND_WATCHER_PID" '.watcher.pid == $pid and .watcher.failures >= 1 and .watcher.last_error == null' >/dev/null; then
    echo "❌ Ready watcher did not remain active after a later observation failure" >&2
    exit 1
fi
stop_supervisor_watcher "$SECOND_WATCHER_PID"
for _ in {1..20}; do
    if [[ ! -d "$XDG_STATE_HOME/codex-pr-monitor/$($STATE_SCRIPT id --pr-url "$SECOND_PR_URL").watch.lock" ]] \
        && ! kill -0 "$SECOND_WATCHER_PID" 2>/dev/null; then
        break
    fi
    sleep 0.05
done
if [[ -d "$XDG_STATE_HOME/codex-pr-monitor/$($STATE_SCRIPT id --pr-url "$SECOND_PR_URL").watch.lock" ]] \
    || kill -0 "$SECOND_WATCHER_PID" 2>/dev/null; then
    echo "❌ Readiness test leaked a monitor watcher" >&2
    exit 1
fi

IMMEDIATE_EXIT_PR_URL="https://github.com/example/repo/pull/44"
"$STATE_SCRIPT" init --pr-url "$IMMEDIATE_EXIT_PR_URL" >/dev/null
"$STATE_SCRIPT" register-pane --pr-url "$IMMEDIATE_EXIT_PR_URL" --pane %77 --nonce 0123456789abcdef >/dev/null
if IMMEDIATE_EXIT_OUTPUT=$(TMUX_STUB_MODE=immediate-exit PR_MONITOR_START_READY_ATTEMPTS=2 PR_MONITOR_START_READY_INTERVAL=0.05 TEST_DIR="$TEST_DIR" "$WATCH_SCRIPT" start --pr-url "$IMMEDIATE_EXIT_PR_URL" 2>&1); then
    echo "❌ Monitor start accepted a tmux window whose child exited immediately" >&2
    exit 1
fi
if [[ "$IMMEDIATE_EXIT_OUTPUT" != *"$IMMEDIATE_EXIT_PR_URL"* ]] \
    || [[ "$IMMEDIATE_EXIT_OUTPUT" != *"\$resume-pr-monitor $IMMEDIATE_EXIT_PR_URL"* ]] \
    || ! "$STATE_SCRIPT" show --pr-url "$IMMEDIATE_EXIT_PR_URL" | jq -e '.watcher.pid == null and .watcher.last_error == "foreground_required"' >/dev/null \
    || ! grep -Fq 'kill-window -t @101' "$TEST_DIR/tmux.log"; then
    echo "❌ Monitor readiness timeout did not remove the window and persist recovery" >&2
    exit 1
fi
: > "$TEST_DIR/tmux.log"

echo "Testing readiness remains valid across a bounded lifecycle observation..."
READY_EXIT_PR_URL="https://github.com/example/repo/pull/48"
"$STATE_SCRIPT" init --pr-url "$READY_EXIT_PR_URL" >/dev/null
"$STATE_SCRIPT" register-pane --pr-url "$READY_EXIT_PR_URL" --pane %77 --nonce 0123456789abcdef >/dev/null
if READY_EXIT_OUTPUT=$(TMUX_STUB_MODE=ready-then-exit TMUX_READY_EXIT_PR_URL="$READY_EXIT_PR_URL" GH_STUB_OPEN=1 GH_STUB_CHECKS_PASS=1 PR_MONITOR_INTERVAL=1 PR_MONITOR_START_READY_ATTEMPTS=10 PR_MONITOR_START_READY_INTERVAL=0.05 TEST_DIR="$TEST_DIR" "$WATCH_SCRIPT" start --pr-url "$READY_EXIT_PR_URL" 2>&1); then
    printf '%s\n' "$READY_EXIT_OUTPUT" >&2
    cat "$TEST_DIR/tmux.log" >&2 || true
    cat "$TEST_DIR/tmux-child.log" >&2 || true
    echo "❌ Monitor start accepted a watcher that exited after its first readiness observation" >&2
    exit 1
fi
for _ in {1..100}; do
    [[ -f "$TEST_DIR/ready-then-exit-recorded" ]] \
        && [[ ! -d "$XDG_STATE_HOME/codex-pr-monitor/$($STATE_SCRIPT id --pr-url "$READY_EXIT_PR_URL").watch.lock" ]] \
        && break
    sleep 0.01
done
if [[ ! -f "$TEST_DIR/ready-then-exit-recorded" ]] \
    || [[ "$READY_EXIT_OUTPUT" == *"started $READY_EXIT_PR_URL"* ]] \
    || ! "$STATE_SCRIPT" show --pr-url "$READY_EXIT_PR_URL" | jq -e '.watcher.pid == null and .watcher.last_error == "foreground_required"' >/dev/null; then
    cat "$TEST_DIR/tmux.log" >&2
    "$STATE_SCRIPT" show --pr-url "$READY_EXIT_PR_URL" >&2 || true
    echo "❌ Readiness timeout did not fail closed after the watcher exited" >&2
    exit 1
fi
stop_tmux_children
: > "$TEST_DIR/tmux.log"

echo "Testing malformed tmux window output is never used as a cleanup target..."
for INVALID_WINDOW_ID in %0 session:window; do
    INVALID_WINDOW_PR_URL="https://github.com/example/repo/pull/$((50 + ${#INVALID_WINDOW_ID}))"
    "$STATE_SCRIPT" init --pr-url "$INVALID_WINDOW_PR_URL" >/dev/null
    "$STATE_SCRIPT" register-pane --pr-url "$INVALID_WINDOW_PR_URL" --pane %77 --nonce 0123456789abcdef >/dev/null
    if INVALID_WINDOW_OUTPUT=$(TMUX_STUB_MODE=immediate-exit TMUX_STUB_WINDOW_OUTPUT="$INVALID_WINDOW_ID" TEST_DIR="$TEST_DIR" "$WATCH_SCRIPT" start --pr-url "$INVALID_WINDOW_PR_URL" 2>&1); then
        echo "❌ Monitor start accepted malformed tmux window output: $INVALID_WINDOW_ID" >&2
        exit 1
    fi
    if [[ "$INVALID_WINDOW_OUTPUT" != *"$INVALID_WINDOW_PR_URL"* ]] \
        || grep -Fq "kill-window -t $INVALID_WINDOW_ID" "$TEST_DIR/tmux.log"; then
        cat "$TEST_DIR/tmux.log" >&2
        echo "❌ Monitor attempted arbitrary cleanup for malformed tmux output: $INVALID_WINDOW_ID" >&2
        exit 1
    fi
    : > "$TEST_DIR/tmux.log"
done

echo "Testing concurrent starts accept only their own launched watcher..."
SIMULTANEOUS_PR_URL="https://github.com/example/repo/pull/46"
"$STATE_SCRIPT" init --pr-url "$SIMULTANEOUS_PR_URL" >/dev/null
"$STATE_SCRIPT" register-pane --pr-url "$SIMULTANEOUS_PR_URL" --pane %77 --nonce 0123456789abcdef >/dev/null
TMUX_STUB_MODE=simultaneous GH_STUB_OPEN=1 GH_STUB_CHECKS_PASS=1 PR_MONITOR_INTERVAL=1 PR_MONITOR_START_READY_ATTEMPTS=100 TEST_DIR="$TEST_DIR" "$WATCH_SCRIPT" start --pr-url "$SIMULTANEOUS_PR_URL" > "$TEST_DIR/simultaneous-one.log" 2>&1 &
SIMULTANEOUS_ONE_PID=$!
TMUX_STUB_MODE=simultaneous GH_STUB_OPEN=1 GH_STUB_CHECKS_PASS=1 PR_MONITOR_INTERVAL=1 PR_MONITOR_START_READY_ATTEMPTS=100 TEST_DIR="$TEST_DIR" "$WATCH_SCRIPT" start --pr-url "$SIMULTANEOUS_PR_URL" > "$TEST_DIR/simultaneous-two.log" 2>&1 &
SIMULTANEOUS_TWO_PID=$!
wait "$SIMULTANEOUS_ONE_PID" || true
wait "$SIMULTANEOUS_TWO_PID" || true
SIMULTANEOUS_STARTED_COUNT=$({ grep -hF "started $SIMULTANEOUS_PR_URL codex-pr-monitor-" "$TEST_DIR/simultaneous-one.log" "$TEST_DIR/simultaneous-two.log" 2>/dev/null || true; } | wc -l | tr -d ' ')
SIMULTANEOUS_LAUNCH_TOKEN=$(jq -r '.launch_token // empty' "$XDG_STATE_HOME/codex-pr-monitor/$($STATE_SCRIPT id --pr-url "$SIMULTANEOUS_PR_URL").watch.lock/owner.json" 2>/dev/null || true)
if [[ "$SIMULTANEOUS_STARTED_COUNT" -ne 1 ]] \
    || [[ ! "$SIMULTANEOUS_LAUNCH_TOKEN" =~ ^[A-Za-z0-9_.-]+$ ]] \
    || ! grep -Fq "PR_MONITOR_LAUNCH_TOKEN=$SIMULTANEOUS_LAUNCH_TOKEN" "$TEST_DIR/tmux.log"; then
    cat "$TEST_DIR/simultaneous-one.log" >&2
    cat "$TEST_DIR/simultaneous-two.log" >&2
    cat "$TEST_DIR/tmux.log" >&2
    "$STATE_SCRIPT" show --pr-url "$SIMULTANEOUS_PR_URL" >&2 || true
    cat "$XDG_STATE_HOME/codex-pr-monitor/$($STATE_SCRIPT id --pr-url "$SIMULTANEOUS_PR_URL").watch.lock/owner.json" >&2 || true
    echo "❌ Concurrent starts accepted a watcher from a different launch" >&2
    exit 1
fi
SIMULTANEOUS_WATCHER_PID=$("$STATE_SCRIPT" show --pr-url "$SIMULTANEOUS_PR_URL" | jq -r '.watcher.pid')
if [[ "$SIMULTANEOUS_WATCHER_PID" =~ ^[0-9]+$ ]]; then
    stop_supervisor_watcher "$SIMULTANEOUS_WATCHER_PID"
else
    stop_tmux_children
fi
: > "$TEST_DIR/tmux.log"

echo "Testing timeout cleanup preserves a healthy successor..."
HANDOFF_PR_URL="https://github.com/example/repo/pull/45"
"$STATE_SCRIPT" init --pr-url "$HANDOFF_PR_URL" >/dev/null
"$STATE_SCRIPT" register-pane --pr-url "$HANDOFF_PR_URL" --pane %77 --nonce 0123456789abcdef >/dev/null
if TMUX_STUB_MODE=handoff TMUX_HANDOFF_PR_URL="$HANDOFF_PR_URL" PR_MONITOR_START_READY_ATTEMPTS=2 PR_MONITOR_START_READY_INTERVAL=0.05 TEST_DIR="$TEST_DIR" "$WATCH_SCRIPT" start --pr-url "$HANDOFF_PR_URL" >/dev/null 2>&1; then
    echo "❌ Timed-out start reported its replaced monitor as ready" >&2
    exit 1
fi
for _ in {1..100}; do
    "$STATE_SCRIPT" show --pr-url "$HANDOFF_PR_URL" | jq -e '.watcher.pid != null and .watcher.last_error == null' >/dev/null && break
    sleep 0.05
done
HANDOFF_WATCHER_PID=$("$STATE_SCRIPT" show --pr-url "$HANDOFF_PR_URL" | jq -r '.watcher.pid')
if [[ ! "$HANDOFF_WATCHER_PID" =~ ^[0-9]+$ ]] \
    || ! "$STATE_SCRIPT" show --pr-url "$HANDOFF_PR_URL" | jq -e --argjson pid "$HANDOFF_WATCHER_PID" '.watcher.pid == $pid and .watcher.last_error == null' >/dev/null \
    || ! kill -0 "$HANDOFF_WATCHER_PID" 2>/dev/null; then
    "$STATE_SCRIPT" show --pr-url "$HANDOFF_PR_URL" >&2 || true
    cat "$TEST_DIR/tmux-successor.log" >&2 || true
    cat "$TEST_DIR/tmux.log" >&2
    echo "❌ Timed-out start clobbered its healthy successor state" >&2
    exit 1
fi
stop_tmux_children
: > "$TEST_DIR/tmux.log"

echo "Testing pane-registration fallback reports the canonical resume command..."
PANE_FAILURE_PR_URL="https://github.com/example/repo/pull/47"
"$STATE_SCRIPT" init --pr-url "$PANE_FAILURE_PR_URL" >/dev/null
if PANE_FAILURE_OUTPUT=$(TEST_DIR="$TEST_DIR" "$WATCH_SCRIPT" start --pr-url "$PANE_FAILURE_PR_URL" 2>&1); then
    echo "❌ Monitor start accepted a missing pane registration" >&2
    exit 1
fi
if [[ "$PANE_FAILURE_OUTPUT" != *"\$resume-pr-monitor $PANE_FAILURE_PR_URL"* ]]; then
    echo "❌ Pane-registration failure omitted the canonical resume command" >&2
    exit 1
fi

echo "Testing dispatcher reserves delivery, waits before Enter, and avoids duplicate insertion..."
"$STATE_SCRIPT" register-pane --pr-url "$PR_URL" --pane %77 --nonce 0123456789abcdef >/dev/null
"$STATE_SCRIPT" pane-status --pr-url "$PR_URL" --nonce 0123456789abcdef --session-id session-42 --status ready
UNTRUSTED_RUN_URL="https://example.invalid/\$(injected)"
EXPECTED_DELIVERY="send-keys -t %77 -l -- \$resume-pr-monitor https://github.com/example/repo/pull/42 --event-id ci_failure:1"
"$STATE_SCRIPT" transition --pr-url "$PR_URL" --event ci --value failed --run-url "$UNTRUSTED_RUN_URL"
PR_MONITOR_SUBMIT_DELAY_SECONDS=1 TEST_DIR="$TEST_DIR" "$DISPATCH_SCRIPT" --pr-url "$PR_URL" > "$TEST_DIR/dispatcher.log" 2>&1 &
DISPATCH_PID=$!
for _ in {1..10}; do
    [[ -s "$TEST_DIR/tmux.log" ]] && break
    sleep 0.05
done
TEST_DIR="$TEST_DIR" "$DISPATCH_SCRIPT" --pr-url "$PR_URL"
if [[ "$(wc -l < "$TEST_DIR/tmux.log" | tr -d ' ')" != "1" ]] \
    || ! grep -Fxq "$EXPECTED_DELIVERY" "$TEST_DIR/tmux.log" \
    || grep -Fq 'injected' "$TEST_DIR/tmux.log" \
    || [[ "$("$STATE_SCRIPT" show --pr-url "$PR_URL" | jq -r '.runtime.status')" != "delivering" ]]; then
    echo "❌ Dispatcher did not reserve a single delayed delivery" >&2
    exit 1
fi
if ! wait "$DISPATCH_PID"; then
    cat "$TEST_DIR/dispatcher.log" >&2
    echo "❌ Delayed dispatcher exited before submitting its reserved delivery" >&2
    exit 1
fi
if [[ "$(wc -l < "$TEST_DIR/tmux.log" | tr -d ' ')" != "2" ]] \
    || ! grep -Fxq 'send-keys -t %77 Enter' "$TEST_DIR/tmux.log"; then
    echo "❌ Dispatcher did not submit the delayed prompt" >&2
    exit 1
fi
RESUME_PROMPT="\$resume-pr-monitor $PR_URL --event-id ci_failure:1"
jq -n --arg session session-42 --arg prompt "$RESUME_PROMPT" '{session_id: $session, prompt: $prompt}' | TMUX_PANE=%77 HOME="$TEST_HOME" XDG_STATE_HOME="$TEST_DIR/state" "$PANE_STATE_HOOK" busy
printf '%s\n' '{"session_id":"session-42"}' | TMUX_PANE=%77 HOME="$TEST_HOME" XDG_STATE_HOME="$TEST_DIR/state" "$PANE_STATE_HOOK" ready
TEST_DIR="$TEST_DIR" "$DISPATCH_SCRIPT" --pr-url "$PR_URL"
if [[ "$(wc -l < "$TEST_DIR/tmux.log" | tr -d ' ')" != "2" ]] \
    || [[ "$("$STATE_SCRIPT" show --pr-url "$PR_URL" | jq -r '.events.ci_failure.delivery.status')" != "submitted" ]]; then
    echo "❌ Submitted delivery was injected again" >&2
    exit 1
fi
"$STATE_SCRIPT" transition --pr-url "$PR_URL" --event ci --value ok
"$STATE_SCRIPT" transition --pr-url "$PR_URL" --event ci --value failed --run-url "$UNTRUSTED_RUN_URL"
if [[ "$("$STATE_SCRIPT" show --pr-url "$PR_URL" | jq -r '.events.ci_failure.id')" != "ci_failure:2" ]]; then
    echo "❌ Repeated CI failures did not receive a distinct event ID" >&2
    exit 1
fi
expect_failure "$STATE_SCRIPT" claim --pr-url "$PR_URL" --event ci_failure --event-id ci_failure:1 --lease-id stale-event
"$STATE_SCRIPT" claim --pr-url "$PR_URL" --event ci_failure --event-id ci_failure:2 --lease-id current-event
"$STATE_SCRIPT" release --pr-url "$PR_URL" --event ci_failure --lease-id current-event
"$STATE_SCRIPT" pane-status --pr-url "$PR_URL" --nonce 0123456789abcdef --session-id session-42 --status approval_pending
TEST_DIR="$TEST_DIR" "$DISPATCH_SCRIPT" --pr-url "$PR_URL"
if [[ "$(wc -l < "$TEST_DIR/tmux.log" | tr -d ' ')" != "2" ]]; then
    cat "$TEST_DIR/tmux.log" >&2
    "$STATE_SCRIPT" show --pr-url "$PR_URL" >&2
    echo "❌ Dispatcher sent to an approval-pending pane" >&2
    exit 1
fi
"$STATE_SCRIPT" pane-status --pr-url "$PR_URL" --nonce 0123456789abcdef --session-id session-42 --status ready
"$STATE_SCRIPT" transition --pr-url "$PR_URL" --event close --value MERGED
TEST_DIR="$TEST_DIR" "$DISPATCH_SCRIPT" --pr-url "$PR_URL"
EXPECTED_CLOSE_DELIVERY="send-keys -t %77 -l -- \$resume-pr-monitor https://github.com/example/repo/pull/42 --event-id close:1"
if ! grep -Fxq "$EXPECTED_CLOSE_DELIVERY" "$TEST_DIR/tmux.log"; then
    echo "❌ Dispatcher did not deliver the pending close event" >&2
    exit 1
fi
STATE_ID=$("$STATE_SCRIPT" id --pr-url "$PR_URL")
STATE_FILE="$XDG_STATE_HOME/codex-pr-monitor/${STATE_ID}.json"
jq '.pr.url = "https://github.com/example/repo/pull/999"' "$STATE_FILE" > "$STATE_FILE.tmp"
mv "$STATE_FILE.tmp" "$STATE_FILE"
expect_failure "$STATE_SCRIPT" show --pr-url "$PR_URL"
rm -f "$STATE_FILE"
"$STATE_SCRIPT" init --pr-url "$PR_URL" >/dev/null

LOCK_DIR="$XDG_STATE_HOME/codex-pr-monitor/${STATE_ID}.lock"
mkdir "$LOCK_DIR"
jq -n --arg token stale --argjson pid 999999 --argjson created "$(date +%s)" '{token: $token, pid: $pid, created_at_epoch: $created}' > "$LOCK_DIR/owner.json"
"$STATE_SCRIPT" transition --pr-url "$PR_URL" --event conflict --value clear

mkdir "$LOCK_DIR"
jq -n --arg token live --arg identity "$(process_identity "$$")" --argjson pid "$$" --argjson created "$(date +%s)" '{token: $token, pid: $pid, process_identity: $identity, created_at_epoch: $created}' > "$LOCK_DIR/owner.json"
expect_failure env PR_MONITOR_LOCK_ATTEMPTS=1 "$STATE_SCRIPT" transition --pr-url "$PR_URL" --event conflict --value conflicting
rm -f "$LOCK_DIR/owner.json"
rmdir "$LOCK_DIR"

sleep 30 &
SLEEP_PID=$!
mkdir "$LOCK_DIR"
jq -n --arg token unrelated --arg identity 'ps-lstart:wrong-process' --argjson pid "$SLEEP_PID" --argjson created 0 '{token: $token, pid: $pid, process_identity: $identity, created_at_epoch: $created}' > "$LOCK_DIR/owner.json"
"$STATE_SCRIPT" transition --pr-url "$PR_URL" --event conflict --value conflicting
if [[ -d "$LOCK_DIR" ]] || ! "$STATE_SCRIPT" show --pr-url "$PR_URL" | jq -e '.observed.conflict == "conflicting"' >/dev/null; then
    echo "❌ State mutation did not recover a live unrelated PID with mismatched identity" >&2
    exit 1
fi
kill "$SLEEP_PID" 2>/dev/null || true
wait "$SLEEP_PID" 2>/dev/null || true
SLEEP_PID=""

WATCH_LOCK="$XDG_STATE_HOME/codex-pr-monitor/${STATE_ID}.watch.lock"
sleep 30 &
SLEEP_PID=$!
mkdir "$WATCH_LOCK"
jq -n --arg token unrelated --arg identity 'ps-lstart:wrong-process' --argjson pid "$SLEEP_PID" --argjson created 0 '{token: $token, pid: $pid, process_identity: $identity, created_at_epoch: $created}' > "$WATCH_LOCK/owner.json"
PR_MONITOR_INTERVAL=0 "$WATCH_SCRIPT" watch --pr-url "$PR_URL"
if [[ -d "$WATCH_LOCK" ]]; then
    echo "❌ Watcher did not recover a live unrelated PID with mismatched identity" >&2
    exit 1
fi
kill "$SLEEP_PID" 2>/dev/null || true
wait "$SLEEP_PID" 2>/dev/null || true
SLEEP_PID=""

echo "Testing concurrent per-event claims and lease-safe acknowledgement..."
"$STATE_SCRIPT" transition --pr-url "$PR_URL" --event close --value MERGED
"$STATE_SCRIPT" claim --pr-url "$PR_URL" --event close --action cleanup --lease-id first
expect_failure "$STATE_SCRIPT" claim --pr-url "$PR_URL" --event close --action cleanup --lease-id second
expect_failure "$STATE_SCRIPT" ack --pr-url "$PR_URL" --event close --action cleanup --lease-id second
"$STATE_SCRIPT" release --pr-url "$PR_URL" --event close --action cleanup --lease-id first
"$STATE_SCRIPT" claim --pr-url "$PR_URL" --event close --action cleanup --lease-id second
"$STATE_SCRIPT" ack --pr-url "$PR_URL" --event close --action cleanup --lease-id second

"$STATE_SCRIPT" transition --pr-url "$PR_URL" --event ci --value failed --run-url https://github.com/example/repo/actions/runs/55
"$STATE_SCRIPT" claim --pr-url "$PR_URL" --event ci_failure --lease-id heartbeat --lease-seconds 1
"$STATE_SCRIPT" renew --pr-url "$PR_URL" --event ci_failure --lease-id heartbeat --lease-seconds 300
if ! "$STATE_SCRIPT" show --pr-url "$PR_URL" | jq -e '.events.ci_failure.lease.expires_at_epoch >= (now | floor) + 299' >/dev/null; then
    echo "❌ Lease heartbeat did not extend active action ownership" >&2
    exit 1
fi
expect_failure "$STATE_SCRIPT" claim --pr-url "$PR_URL" --event ci_failure --lease-id competing
"$STATE_SCRIPT" release --pr-url "$PR_URL" --event ci_failure --lease-id heartbeat
"$STATE_SCRIPT" transition --pr-url "$PR_URL" --event ci --value ok

"$STATE_SCRIPT" transition --pr-url "$PR_URL" --event copilot --value detected
("$STATE_SCRIPT" claim --pr-url "$PR_URL" --event copilot_review --lease-id parallel-one) > "$TEST_DIR/parallel-one.log" 2>&1 &
CLAIM_ONE_PID=$!
("$STATE_SCRIPT" claim --pr-url "$PR_URL" --event copilot_review --lease-id parallel-two) > "$TEST_DIR/parallel-two.log" 2>&1 &
CLAIM_TWO_PID=$!
CLAIM_SUCCESSES=0
if wait "$CLAIM_ONE_PID"; then
    CLAIM_SUCCESSES=$((CLAIM_SUCCESSES + 1))
fi
if wait "$CLAIM_TWO_PID"; then
    CLAIM_SUCCESSES=$((CLAIM_SUCCESSES + 1))
fi
if [[ "$CLAIM_SUCCESSES" -ne 1 ]]; then
    echo "❌ Concurrent resume claims did not elect exactly one owner" >&2
    exit 1
fi
if "$STATE_SCRIPT" show --pr-url "$PR_URL" | jq -e '.events.copilot_review.lease.id == "parallel-one"' >/dev/null; then
    "$STATE_SCRIPT" release --pr-url "$PR_URL" --event copilot_review --lease-id parallel-one
else
    "$STATE_SCRIPT" release --pr-url "$PR_URL" --event copilot_review --lease-id parallel-two
fi

echo "Testing reconciliation, actionable CI event, and terminal watcher exit..."
WATCH_LOCK="$XDG_STATE_HOME/codex-pr-monitor/${STATE_ID}.watch.lock"
mkdir "$WATCH_LOCK"
jq -n --arg token live --arg launch_token existing-launch-token --arg identity "$(process_identity "$$")" --argjson pid "$$" --argjson created "$(date +%s)" \
    '{token: $token, launch_token: $launch_token, pid: $pid, process_identity: $identity, created_at_epoch: $created}' > "$WATCH_LOCK/owner.json"
"$STATE_SCRIPT" watcher --pr-url "$PR_URL" --pid 999999
if UNREADY_REUSE_OUTPUT=$(PR_MONITOR_START_READY_ATTEMPTS=2 PR_MONITOR_START_READY_INTERVAL=0.05 "$WATCH_SCRIPT" start --pr-url "$PR_URL" 2>&1); then
    echo "❌ Watcher start reported an unready live lock as active" >&2
    exit 1
fi
if [[ "$UNREADY_REUSE_OUTPUT" == *"reused $PR_URL"* ]]; then
    echo "❌ Unready live-lock reuse claimed readiness" >&2
    exit 1
fi
if ! "$STATE_SCRIPT" show --pr-url "$PR_URL" | jq -e '.watcher.pid == null and .watcher.last_error == "foreground_required"' >/dev/null; then
    echo "❌ Unready live-lock reuse did not record a foreground_required diagnostic" >&2
    exit 1
fi
"$STATE_SCRIPT" watcher --pr-url "$PR_URL" --pid "$$"
STATE_BEFORE_REUSE=$("$STATE_SCRIPT" show --pr-url "$PR_URL")
START_OUTPUT=$("$WATCH_SCRIPT" start --pr-url "$PR_URL")
STATE_AFTER_REUSE=$("$STATE_SCRIPT" show --pr-url "$PR_URL")
if [[ "$START_OUTPUT" != "reused $PR_URL" || "$STATE_AFTER_REUSE" != "$STATE_BEFORE_REUSE" ]]; then
    echo "❌ Watcher start did not preserve a live watcher state" >&2
    exit 1
fi
rm -f "$WATCH_LOCK/owner.json"
rmdir "$WATCH_LOCK"

if "$WATCH_SCRIPT" start --pr-url "$PR_URL" >/dev/null 2>&1; then
    echo "❌ Watcher start claimed detached monitoring" >&2
    exit 1
fi
if ! "$STATE_SCRIPT" show --pr-url "$PR_URL" | jq -e '.watcher.pid == null and .watcher.last_error == "foreground_required"' >/dev/null; then
    echo "❌ Foreground fallback did not persist a terminal diagnostic" >&2
    exit 1
fi
if [[ -d "$XDG_STATE_HOME/codex-pr-monitor/${STATE_ID}.watch.lock" ]]; then
    echo "❌ Foreground fallback left a watcher lock" >&2
    exit 1
fi
if grep -En 'nohup|systemd-run|setsid' "$WATCH_SCRIPT" >/dev/null; then
    echo "❌ Watcher still contains an unverified detached-launch path" >&2
    exit 1
elif [[ $? -ne 1 ]]; then
    echo "❌ Failed to check watcher for detached-launch paths" >&2
    exit 1
fi

GH_STUB_CONVERSATION_COMMENTS=1 GH_STUB_REVIEWS=1 GH_STUB_REVIEW_COMMENTS=1 "$WATCH_SCRIPT" once --pr-url "$PR_URL"
if ! "$STATE_SCRIPT" show --pr-url "$PR_URL" | jq -e '.events.ci_failure.run_url == "https://github.com/example/repo/actions/runs/123" and .events.review_feedback.status == "pending" and .events.review_feedback.value == 3' >/dev/null; then
    echo "❌ Reconciliation did not atomically retain actionable CI and review feedback events" >&2
    exit 1
fi
echo "Testing feedback arriving during handling produces one settling follow-up..."
"$STATE_SCRIPT" claim --pr-url "$PR_URL" --event review_feedback --event-id review_feedback:1 --lease-id feedback-one
"$STATE_SCRIPT" transition --pr-url "$PR_URL" --event review-feedback --value 4
"$STATE_SCRIPT" ack --pr-url "$PR_URL" --event review_feedback --lease-id feedback-one
if ! "$STATE_SCRIPT" show --pr-url "$PR_URL" | jq -e '.events.review_feedback.id == "review_feedback:2" and .events.review_feedback.status == "pending" and .events.review_feedback.value == 4' >/dev/null; then
    echo "❌ New feedback during handling was not retained as a follow-up event" >&2
    exit 1
fi
"$STATE_SCRIPT" claim --pr-url "$PR_URL" --event review_feedback --event-id review_feedback:2 --lease-id feedback-two
"$STATE_SCRIPT" ack --pr-url "$PR_URL" --event review_feedback --lease-id feedback-two
if ! "$STATE_SCRIPT" show --pr-url "$PR_URL" | jq -e '.generations.review_feedback == 2 and .events.review_feedback.status == "acknowledged" and .events.review_feedback.follow_up == false' >/dev/null; then
    echo "❌ Review feedback follow-up did not settle after acknowledgement" >&2
    exit 1
fi
if PR_MONITOR_INTERVAL=0 "$WATCH_SCRIPT" watch --pr-url "$PR_URL"; then
    :
fi
if ! "$STATE_SCRIPT" show --pr-url "$PR_URL" | jq -e '.watcher.pid == null and .events.close.value == "MERGED"' >/dev/null; then
    echo "❌ Terminal watcher did not enqueue final events and release itself" >&2
    exit 1
fi
if [[ -d "$XDG_STATE_HOME/codex-pr-monitor/${STATE_ID}.watch.lock" ]]; then
    echo "❌ Terminal watcher did not release its owned lock" >&2
    exit 1
fi

echo "Testing observer/action boundary..."
if grep -Eq 'tmux|handle-pr-reviews' "$COPILOT_SCRIPT"; then
    echo "❌ Copilot observer can still invoke an action processor" >&2
    exit 1
fi
echo "Testing five-failure stop state..."
if GH_STUB_FAILURE=1 PR_MONITOR_INTERVAL=0 PR_MONITOR_MAX_POLLS=5 "$WATCH_SCRIPT" watch --pr-url "$PR_URL"; then
    echo "❌ Watcher did not stop after five API failures" >&2
    exit 1
fi
if ! "$STATE_SCRIPT" show --pr-url "$PR_URL" | jq -e '.watcher.failures == 5 and .watcher.pid == null' >/dev/null; then
    echo "❌ Watcher did not persist the terminal API failure state" >&2
    exit 1
fi

echo "Testing a new Codex session cannot reactivate a stopped registration..."
"$STATE_SCRIPT" register-pane --pr-url "$PR_URL" --pane %77 --nonce 0123456789abcdef >/dev/null
"$STATE_SCRIPT" pane-status --pr-url "$PR_URL" --nonce 0123456789abcdef --session-id session-42 --status ready
printf '%s\n' '{"session_id":"session-42"}' | TMUX_PANE=%77 HOME="$TEST_HOME" XDG_STATE_HOME="$TEST_DIR/state" "$PANE_STATE_HOOK" stopped
printf '%s\n' '{"session_id":"session-other"}' | TMUX_PANE=%77 HOME="$TEST_HOME" XDG_STATE_HOME="$TEST_DIR/state" "$PANE_STATE_HOOK" ready
if [[ "$("$STATE_SCRIPT" show --pr-url "$PR_URL" | jq -r '.runtime.status')" != "stopped" ]]; then
    echo "❌ A new Codex session reactivated a stopped pane registration" >&2
    exit 1
fi

echo "✅ PR monitor state and watcher tests passed"
