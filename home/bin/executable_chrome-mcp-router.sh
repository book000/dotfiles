#!/bin/bash
# Chrome MCP Router の固定ローカル起動スクリプト

set -euo pipefail

INSTALL_DIR="${CHROME_MCP_INSTALL_DIR:-$HOME/.local/share/chrome-mcp-router}"
CURRENT_DIR="$INSTALL_DIR/current"
ROUTER="$CURRENT_DIR/node_modules/.bin/chrome-mcp-router"
UPDATER="$HOME/bin/update-ai-agents.sh"

# 更新は別プロセスで開始し、MCP の initialize を待たせない。
if [[ -x "$UPDATER" ]]; then
    "$UPDATER" --quick --only chrome-mcp-router > /dev/null 2>&1 &
fi

if [[ ! -x "$ROUTER" ]]; then
    echo "Error: Chrome MCP Router is not installed. Run update-ai-agents.sh --only chrome-mcp-router." >&2
    exit 1
fi

# router が同じ release の chrome-devtools-mcp を必ず見つけられるようにする。
export PATH="$CURRENT_DIR/node_modules/.bin:$PATH"
exec "$ROUTER" "$@"
