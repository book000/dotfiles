#!/bin/bash
# Chrome MCP launcher and updater のユニットテスト
set -euo pipefail

LAUNCHER="$(pwd)/home/bin/executable_chrome-mcp-router.sh"
UPDATER="$(pwd)/home/bin/executable_update-ai-agents.sh"

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
cat > "$prefix/node_modules/.bin/chrome-mcp-router" <<'ROUTER'
#!/bin/bash
while IFS= read -r line; do
    printf '%s\n' "$line" >> "${CHROME_ROUTER_INPUT:?}"
    if [[ "${FAKE_MCP_SMOKE_MODE:-success}" == "success" ]]; then
        printf '%s\n' '{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-06-18","capabilities":{},"serverInfo":{"name":"fake-router","version":"1.0.0"}}}'
    fi
    exit 0
done
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
        exit 1
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
EOF
cat > "$LAUNCHER_BIN/npx" <<'EOF'
#!/bin/bash
exit 99
EOF
chmod +x "$LAUNCHER_HOME/bin/update-ai-agents.sh" "$LAUNCHER_BIN/npx"
: > "$TEST_ROOT/launcher-router-input"
SECONDS=0
HOME="$LAUNCHER_HOME" PATH="$LAUNCHER_BIN:/usr/bin:/bin" CHROME_ROUTER_ARGS="$TEST_ROOT/launcher-router-args" CHROME_ROUTER_INPUT="$TEST_ROOT/launcher-router-input" FAKE_UPDATER_LOG="$TEST_ROOT/launcher-updater" bash "$LAUNCHER" --browserUrl http://127.0.0.1:9222 < /dev/null
[[ $SECONDS -lt 1 ]] || fail "launcher waited for the updater"
[[ "$(cat "$TEST_ROOT/launcher-router-args")" == "--browserUrl http://127.0.0.1:9222" ]] || fail "launcher did not execute the current router"
for _ in $(seq 1 30); do
    [[ -f "$TEST_ROOT/launcher-updater" ]] && break
    sleep 0.1
done
[[ "$(cat "$TEST_ROOT/launcher-updater")" == "--quick --only chrome-mcp-router" ]] || fail "launcher did not request the throttled MCP update"
echo "✅ local launcher startup test passed"

echo "Testing a successful update promotes a smoke-tested release atomically..."
SUCCESS_HOME="$TEST_ROOT/success-home"
SUCCESS_BIN="$TEST_ROOT/success-bin"
mkdir -p "$SUCCESS_BIN"
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
HOME="$SUCCESS_HOME" PATH="$SUCCESS_BIN:/usr/bin:/bin" FAKE_NPM_LOG="$TEST_ROOT/success-npm.log" CHROME_ROUTER_INPUT="$TEST_ROOT/success-router-input" CHROME_MCP_SMOKE_TIMEOUT_SECONDS=1 bash "$UPDATER" --only chrome-mcp-router
kill -0 "$HOLD_PID" 2>/dev/null || fail "updater terminated a running process from the old release"
kill "$HOLD_PID"
wait "$HOLD_PID" 2>/dev/null || true
SUCCESS_CURRENT=$(readlink -f "$SUCCESS_HOME/.local/share/chrome-mcp-router/current")
[[ "$SUCCESS_CURRENT" != "$SUCCESS_OLD_RELEASE" ]] || fail "successful update did not promote a new release"
grep -Fq 'chrome-mcp-router@latest' "$TEST_ROOT/success-npm.log" || fail "updater did not resolve the router latest version"
grep -Fq 'chrome-devtools-mcp@latest' "$TEST_ROOT/success-npm.log" || fail "updater did not resolve the devtools latest version"
grep -Fq '"method":"initialize"' "$TEST_ROOT/success-router-input" || fail "updater did not run MCP initialize smoke test"
[[ -f "$SUCCESS_HOME/.cache/update-ai-agents/last-update-chrome-mcp-router" ]] || fail "successful update did not record its timestamp"
echo "✅ successful staged update test passed"

echo "Testing a failed smoke test keeps the previous current release..."
FAILURE_HOME="$TEST_ROOT/failure-home"
FAILURE_BIN="$TEST_ROOT/failure-bin"
mkdir -p "$FAILURE_BIN"
FAILURE_OLD_RELEASE=$(make_release "$FAILURE_HOME" old)
set_current_release "$FAILURE_HOME" "$FAILURE_OLD_RELEASE"
make_fake_npm "$FAILURE_BIN"
make_fake_curl "$FAILURE_BIN"
make_fake_node "$FAILURE_BIN"
: > "$TEST_ROOT/failure-router-input"
set +e
HOME="$FAILURE_HOME" PATH="$FAILURE_BIN:/usr/bin:/bin" FAKE_NPM_LOG="$TEST_ROOT/failure-npm.log" CHROME_ROUTER_INPUT="$TEST_ROOT/failure-router-input" FAKE_MCP_SMOKE_MODE=fail CHROME_MCP_SMOKE_TIMEOUT_SECONDS=1 bash "$UPDATER" --only chrome-mcp-router
FAILURE_RC=$?
set -e
[[ $FAILURE_RC -ne 0 ]] || fail "updater succeeded despite the failed MCP smoke test"
[[ "$(readlink -f "$FAILURE_HOME/.local/share/chrome-mcp-router/current")" == "$FAILURE_OLD_RELEASE" ]] || fail "failed update replaced the previous current release"
[[ ! -f "$FAILURE_HOME/.cache/update-ai-agents/last-update-chrome-mcp-router" ]] || fail "failed update recorded a successful timestamp"
echo "✅ failed smoke test rollback test passed"
