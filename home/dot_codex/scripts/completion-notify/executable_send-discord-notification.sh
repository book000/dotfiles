#!/bin/bash
# Codex CLI の Discord 通知を送信する。

set -euo pipefail

cd "$(dirname "$0")" || exit 1
# shellcheck source=/dev/null
source ./.env

PAYLOAD=$(cat)
if [[ -z "$PAYLOAD" ]]; then
    exit 0
fi

if [[ -z "${DISCORD_WEBHOOK_URL:-}" ]]; then
    exit 0
fi

DATA_DIR="$HOME/.codex/scripts/completion-notify/data"
LOG_FILE="$DATA_DIR/discord-notify.log"
mkdir -p "$DATA_DIR"

set +e
HTTP_STATUS=$(curl -sS -o /dev/null -w "%{http_code}" \
    --connect-timeout 10 \
    --max-time 30 \
    --retry 2 \
    --retry-delay 1 \
    --retry-connrefused \
    -H "Content-Type: application/json" \
    -X POST \
    -d "$PAYLOAD" \
    "$DISCORD_WEBHOOK_URL" 2>>"$LOG_FILE")
EXIT_CODE=$?
set -e

if [[ $EXIT_CODE -ne 0 || -z "$HTTP_STATUS" || $HTTP_STATUS -lt 200 || $HTTP_STATUS -ge 300 ]]; then
    {
        printf '%s ' "$(date --iso-8601=seconds 2>/dev/null || date -Iseconds)"
        printf 'ERROR: Failed to send Discord notification (exit=%s, http_status=%s)\n' "$EXIT_CODE" "${HTTP_STATUS:-unknown}"
    } >>"$LOG_FILE"
fi

exit 0
