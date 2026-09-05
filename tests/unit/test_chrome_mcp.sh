#!/bin/bash
# Chrome MCP launcher and updater のユニットテスト
set -euo pipefail

LAUNCHER="$(pwd)/home/bin/executable_chrome-mcp-router.sh"
UPDATER="$(pwd)/home/bin/executable_update-ai-agents.sh"
SMOKE_HELPER="$(pwd)/home/bin/chrome-mcp-smoke-test.mjs"
REAL_NODE="$(node -p 'process.execPath')"

TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT

fail() {
    echo "❌ $*"
    exit 1
}

make_release() {
    local home="$1"
    local name="$2"
    local release="$home/.local/share/chrome-mcp-router/releases/$name"

    mkdir -p "$release/node_modules/.bin"
    cat > "$release/node_modules/.bin/chrome-mcp-router" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" > "${CHROME_ROUTER_ARGS:?}"
while IFS= read -r line; do
    printf '%s\n' "$line" >> "${CHROME_ROUTER_INPUT:?}"
    case "${FAKE_MCP_SMOKE_MODE:-success}" in
        success)
            printf '%s\n' '{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-06-18","capabilities":{},"serverInfo":{"name":"fake-router","version":"1.0.0"}}}'
            ;;
        fail)
            exit 0
            ;;
    esac
done
EOF
    chmod +x "$release/node_modules/.bin/chrome-mcp-router"
    printf '{"name":"chrome-mcp-router","version":"%s"}\n' "$name" > "$release/node_modules/chrome-mcp-router-package.json"
    printf '{"name":"chrome-devtools-mcp","version":"%s"}\n' "$name" > "$release/node_modules/chrome-devtools-mcp-package.json"
    printf '%s\n' "$release"
}

set_current_release() {
    local home="$1"
    local release="$2"
    local install_dir="$home/.local/share/chrome-mcp-router"

    mkdir -p "$install_dir"
    ln -s "${release#"$install_dir/"}" "$install_dir/current"
}

make_fake_npm() {
    local bin_dir="$1"

    cat > "$bin_dir/npm" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "${FAKE_NPM_LOG:?}"
prefix=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --prefix)
            prefix="$2"
            shift 2
            ;;
        *)
            shift
            ;;
    esac
done
[[ -n "$prefix" ]] || exit 1
mkdir -p "$prefix/node_modules/.bin" "$prefix/node_modules/chrome-mcp-router" "$prefix/node_modules/chrome-devtools-mcp"
cat > "$prefix/node_modules/.bin/chrome-devtools-mcp" <<'DEVTOOLS'
#!/bin/bash
exit 0
DEVTOOLS
chmod +x "$prefix/node_modules/.bin/chrome-devtools-mcp"
cat > "$prefix/node_modules/.bin/chrome-mcp-router" <<'ROUTER'
#!/bin/bash
IFS= read -r line || exit 0
printf '%s\n' "$line" >> "${CHROME_ROUTER_INPUT:?}"
printf '%s\n' "$*" > "${CHROME_ROUTER_ARGS:?}"
command -v chrome-devtools-mcp > "${CHROME_DEVTOOLS_PATH:?}" || exit 1

if [[ "$1" == "--project" ]]; then
    [[ "$2" == "collect-points" ]] || exit 1
    /usr/bin/jq -r --arg project "$2" '.projects[$project].browserUrl' "$HOME/.config/chrome-mcp-router/config.json" > "${CHROME_PROJECT_URL:?}"
fi

if [[ "${FAKE_MCP_SMOKE_MODE:-success}" == "fail" ]]; then
    sleep 30 &
    printf '%s\n' "$!" > "${CHROME_ROUTER_CHILD_PID:?}"
    wait
    exit 0
fi

set +e
IFS= read -r -t 1 ignored
read_rc=$?
set -e
[[ $read_rc -eq 142 ]] || exit 0

printf '%s\n' '{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-06-18","capabilities":{},"serverInfo":{"name":"fake-router","version":"1.0.0"}}}'
set +e
IFS= read -r ignored
eof_rc=$?
set -e
[[ $eof_rc -eq 1 ]] && printf '%s\n' closed > "${CHROME_ROUTER_EOF_LOG:?}"
ROUTER
chmod +x "$prefix/node_modules/.bin/chrome-mcp-router"
printf '{"name":"chrome-mcp-router","version":"2.0.0"}\n' > "$prefix/node_modules/chrome-mcp-router/package.json"
printf '{"name":"chrome-devtools-mcp","version":"3.0.0"}\n' > "$prefix/node_modules/chrome-devtools-mcp/package.json"
EOF
    chmod +x "$bin_dir/npm"
}

make_fake_curl() {
    local bin_dir="$1"
    cat > "$bin_dir/curl" <<'EOF'
#!/bin/bash
exit 0
EOF
    chmod +x "$bin_dir/curl"
}

make_fake_node() {
    local bin_dir="$1"
    cat > "$bin_dir/node" <<'EOF'
#!/bin/bash
last_arg="${!#}"
case "$1" in
    -e)
        printf '%s\n' "$last_arg" | /usr/bin/jq -e '.jsonrpc == "2.0" and .id == 1 and (.result | type == "object")' > /dev/null
        ;;
    -p)
        /usr/bin/jq -r '.version' "$last_arg"
        ;;
    *)
        exec "${REAL_NODE:?}" "$@"
        ;;
esac
EOF
    chmod +x "$bin_dir/node"
}

echo "Testing the launcher uses the current local release without blocking on updates..."
LAUNCHER_HOME="$TEST_ROOT/launcher-home"
LAUNCHER_BIN="$TEST_ROOT/launcher-bin"
mkdir -p "$LAUNCHER_HOME/bin" "$LAUNCHER_BIN"
LAUNCHER_RELEASE=$(make_release "$LAUNCHER_HOME" old)
set_current_release "$LAUNCHER_HOME" "$LAUNCHER_RELEASE"
cat > "$LAUNCHER_HOME/bin/update-ai-agents.sh" <<'EOF'
#!/bin/bash
sleep 2
printf '%s\n' "$*" > "${FAKE_UPDATER_LOG:?}"
printf '%s\n' "${CHROME_MCP_PROJECT:-}" > "${FAKE_UPDATER_PROJECT_LOG:?}"
printf '%s\n' "${CHROME_MCP_BROWSER_URL:-}" > "${FAKE_UPDATER_BROWSER_URL_LOG:?}"
EOF
cat > "$LAUNCHER_BIN/npx" <<'EOF'
#!/bin/bash
exit 99
EOF
chmod +x "$LAUNCHER_HOME/bin/update-ai-agents.sh" "$LAUNCHER_BIN/npx"
: > "$TEST_ROOT/launcher-router-input"
SECONDS=0
HOME="$LAUNCHER_HOME" PATH="$LAUNCHER_BIN:/usr/bin:/bin" CHROME_ROUTER_ARGS="$TEST_ROOT/launcher-router-args" CHROME_ROUTER_INPUT="$TEST_ROOT/launcher-router-input" FAKE_UPDATER_LOG="$TEST_ROOT/launcher-updater" FAKE_UPDATER_PROJECT_LOG="$TEST_ROOT/launcher-updater-project" FAKE_UPDATER_BROWSER_URL_LOG="$TEST_ROOT/launcher-updater-browser-url" bash "$LAUNCHER" --project collect-points < /dev/null
[[ $SECONDS -lt 1 ]] || fail "launcher waited for the updater"
[[ "$(cat "$TEST_ROOT/launcher-router-args")" == "--project collect-points" ]] || fail "launcher did not execute the current router"
for _ in $(seq 1 30); do
    [[ -f "$TEST_ROOT/launcher-updater" ]] && break
    sleep 0.1
done
[[ "$(cat "$TEST_ROOT/launcher-updater")" == "--quick --only chrome-mcp-router" ]] || fail "launcher did not request the throttled MCP update"
[[ "$(cat "$TEST_ROOT/launcher-updater-project")" == "collect-points" ]] || fail "launcher did not propagate the MCP project to the updater"
echo "Testing the launcher propagates direct browser URLs to the updater..."
: > "$TEST_ROOT/launcher-browser-router-input"
HOME="$LAUNCHER_HOME" PATH="$LAUNCHER_BIN:/usr/bin:/bin" CHROME_ROUTER_ARGS="$TEST_ROOT/launcher-browser-router-args" CHROME_ROUTER_INPUT="$TEST_ROOT/launcher-browser-router-input" FAKE_UPDATER_LOG="$TEST_ROOT/launcher-browser-updater" FAKE_UPDATER_PROJECT_LOG="$TEST_ROOT/launcher-browser-updater-project" FAKE_UPDATER_BROWSER_URL_LOG="$TEST_ROOT/launcher-browser-updater-url" bash "$LAUNCHER" --browserUrl http://127.0.0.1:9210 < /dev/null
[[ "$(cat "$TEST_ROOT/launcher-browser-router-args")" == "--browserUrl http://127.0.0.1:9210" ]] || fail "launcher did not execute the direct browser URL router"
for _ in $(seq 1 30); do
    [[ -f "$TEST_ROOT/launcher-browser-updater-url" ]] && break
    sleep 0.1
done
[[ "$(cat "$TEST_ROOT/launcher-browser-updater-project")" == "" ]] || fail "direct browser URL launcher retained an MCP project"
[[ "$(cat "$TEST_ROOT/launcher-browser-updater-url")" == "http://127.0.0.1:9210" ]] || fail "launcher did not propagate the browser URL to the updater"
echo "✅ local launcher startup test passed"

echo "Testing a successful update promotes a smoke-tested release atomically..."
SUCCESS_HOME="$TEST_ROOT/success-home"
SUCCESS_BIN="$TEST_ROOT/success-bin"
mkdir -p "$SUCCESS_BIN" "$SUCCESS_HOME/bin"
ln -s "$SMOKE_HELPER" "$SUCCESS_HOME/bin/chrome-mcp-smoke-test.mjs"
SUCCESS_OLD_RELEASE=$(make_release "$SUCCESS_HOME" old)
set_current_release "$SUCCESS_HOME" "$SUCCESS_OLD_RELEASE"
cat > "$SUCCESS_OLD_RELEASE/hold" <<'EOF'
#!/bin/bash
while :; do sleep 1; done
EOF
chmod +x "$SUCCESS_OLD_RELEASE/hold"
"$SUCCESS_OLD_RELEASE/hold" &
HOLD_PID=$!
make_fake_npm "$SUCCESS_BIN"
make_fake_curl "$SUCCESS_BIN"
make_fake_node "$SUCCESS_BIN"
: > "$TEST_ROOT/success-router-input"
mkdir -p "$SUCCESS_HOME/.config/chrome-mcp-router"
printf '{"projects":{"collect-points":{"browserUrl":"http://127.0.0.1:9210"}}}\n' > "$SUCCESS_HOME/.config/chrome-mcp-router/config.json"
HOME="$SUCCESS_HOME" PATH="$SUCCESS_BIN:/usr/bin:/bin" REAL_NODE="$REAL_NODE" CHROME_MCP_PROJECT=collect-points FAKE_NPM_LOG="$TEST_ROOT/success-npm.log" CHROME_ROUTER_ARGS="$TEST_ROOT/success-router-args" CHROME_ROUTER_INPUT="$TEST_ROOT/success-router-input" CHROME_DEVTOOLS_PATH="$TEST_ROOT/success-devtools-path" CHROME_PROJECT_URL="$TEST_ROOT/success-project-url" CHROME_ROUTER_EOF_LOG="$TEST_ROOT/success-router-eof" CHROME_MCP_SMOKE_TIMEOUT_SECONDS=2 bash "$UPDATER" --only chrome-mcp-router
kill -0 "$HOLD_PID" 2>/dev/null || fail "updater terminated a running process from the old release"
kill "$HOLD_PID"
wait "$HOLD_PID" 2>/dev/null || true
SUCCESS_CURRENT=$(readlink -f "$SUCCESS_HOME/.local/share/chrome-mcp-router/current")
[[ "$SUCCESS_CURRENT" != "$SUCCESS_OLD_RELEASE" ]] || fail "successful update did not promote a new release"
grep -Fq 'chrome-mcp-router@latest' "$TEST_ROOT/success-npm.log" || fail "updater did not resolve the router latest version"
grep -Fq 'chrome-devtools-mcp@latest' "$TEST_ROOT/success-npm.log" || fail "updater did not resolve the devtools latest version"
grep -Fq '"method":"initialize"' "$TEST_ROOT/success-router-input" || fail "updater did not run MCP initialize smoke test"
[[ "$(cat "$TEST_ROOT/success-router-args")" == "--project collect-points" ]] || fail "staged smoke test did not use project mode"
[[ "$(cat "$TEST_ROOT/success-project-url")" == "http://127.0.0.1:9210" ]] || fail "staged smoke test did not resolve the project browser URL"
[[ -f "$TEST_ROOT/success-devtools-path" ]] || fail "smoke router could not find its staged chrome-devtools-mcp binary"
[[ "$(cat "$TEST_ROOT/success-router-eof")" == "closed" ]] || fail "smoke client did not close stdin after initialize response"
[[ -f "$SUCCESS_HOME/.cache/update-ai-agents/last-update-chrome-mcp-router" ]] || fail "successful update did not record its timestamp"
echo "✅ successful staged update test passed"

echo "Testing a failed smoke test keeps the previous current release..."
FAILURE_HOME="$TEST_ROOT/failure-home"
FAILURE_BIN="$TEST_ROOT/failure-bin"
mkdir -p "$FAILURE_BIN" "$FAILURE_HOME/bin"
ln -s "$SMOKE_HELPER" "$FAILURE_HOME/bin/chrome-mcp-smoke-test.mjs"
FAILURE_OLD_RELEASE=$(make_release "$FAILURE_HOME" old)
set_current_release "$FAILURE_HOME" "$FAILURE_OLD_RELEASE"
make_fake_npm "$FAILURE_BIN"
make_fake_curl "$FAILURE_BIN"
make_fake_node "$FAILURE_BIN"
: > "$TEST_ROOT/failure-router-input"
FAILURE_CHILD_PID_FILE="$TEST_ROOT/failure-router-child-pid"
set +e
HOME="$FAILURE_HOME" PATH="$FAILURE_BIN:/usr/bin:/bin" REAL_NODE="$REAL_NODE" FAKE_NPM_LOG="$TEST_ROOT/failure-npm.log" CHROME_ROUTER_ARGS="$TEST_ROOT/failure-router-args" CHROME_ROUTER_INPUT="$TEST_ROOT/failure-router-input" CHROME_DEVTOOLS_PATH="$TEST_ROOT/failure-devtools-path" CHROME_ROUTER_CHILD_PID="$FAILURE_CHILD_PID_FILE" FAKE_MCP_SMOKE_MODE=fail CHROME_MCP_SMOKE_TIMEOUT_SECONDS=1 bash "$UPDATER" --only chrome-mcp-router
FAILURE_RC=$?
set -e
[[ $FAILURE_RC -ne 0 ]] || fail "updater succeeded despite the failed MCP smoke test"
[[ "$(readlink -f "$FAILURE_HOME/.local/share/chrome-mcp-router/current")" == "$FAILURE_OLD_RELEASE" ]] || fail "failed update replaced the previous current release"
[[ ! -f "$FAILURE_HOME/.cache/update-ai-agents/last-update-chrome-mcp-router" ]] || fail "failed update recorded a successful timestamp"
[[ -f "$FAILURE_CHILD_PID_FILE" ]] || fail "failed smoke router did not start its child process"
FAILURE_CHILD_PID=$(cat "$FAILURE_CHILD_PID_FILE")
for _ in $(seq 1 20); do
    kill -0 "$FAILURE_CHILD_PID" 2> /dev/null || break
    sleep 0.1
done
! kill -0 "$FAILURE_CHILD_PID" 2> /dev/null || fail "smoke timeout left a child process running"
echo "✅ failed smoke test rollback test passed"
