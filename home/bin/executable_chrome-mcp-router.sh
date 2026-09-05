#!/bin/bash
# Chrome MCP Router の固定ローカル起動スクリプト

set -euo pipefail

INSTALL_DIR="${CHROME_MCP_INSTALL_DIR:-$HOME/.local/share/chrome-mcp-router}"
CURRENT_DIR="$INSTALL_DIR/current"
ROUTER="$CURRENT_DIR/node_modules/.bin/chrome-mcp-router"
UPDATER="$HOME/bin/update-ai-agents.sh"
PROJECT=""
BROWSER_URL=""
ARGS=("$@")

for ((index = 0; index < ${#ARGS[@]}; index += 1)); do
    argument="${ARGS[index]}"
    case "$argument" in
        --project=*)
            PROJECT="${argument#--project=}"
            ;;
        --project)
            if (( index + 1 < ${#ARGS[@]} )) && [[ "${ARGS[index + 1]}" != --* ]]; then
                PROJECT="${ARGS[index + 1]}"
                index=$((index + 1))
            fi
            ;;
        --browserUrl=*)
            BROWSER_URL="${argument#--browserUrl=}"
            ;;
        --browserUrl)
            if (( index + 1 < ${#ARGS[@]} )) && [[ "${ARGS[index + 1]}" != --* ]]; then
                BROWSER_URL="${ARGS[index + 1]}"
                index=$((index + 1))
            fi
            ;;
    esac
done

# 更新は別プロセスで開始し、MCP の initialize を待たせない。
if [[ -x "$UPDATER" ]]; then
    if [[ -n "$PROJECT" ]]; then
        env -u CHROME_MCP_BROWSER_URL CHROME_MCP_PROJECT="$PROJECT" "$UPDATER" --quick --only chrome-mcp-router > /dev/null 2>&1 &
    elif [[ -n "$BROWSER_URL" ]]; then
        env -u CHROME_MCP_PROJECT CHROME_MCP_BROWSER_URL="$BROWSER_URL" "$UPDATER" --quick --only chrome-mcp-router > /dev/null 2>&1 &
    else
        env -u CHROME_MCP_PROJECT "$UPDATER" --quick --only chrome-mcp-router > /dev/null 2>&1 &
    fi
fi

if [[ ! -x "$ROUTER" ]]; then
    echo "Error: Chrome MCP Router is not installed. Run update-ai-agents.sh --only chrome-mcp-router." >&2
    exit 1
fi

# router が同じ release の chrome-devtools-mcp を必ず見つけられるようにする。
export PATH="$CURRENT_DIR/node_modules/.bin:$PATH"
exec "$ROUTER" "$@"
