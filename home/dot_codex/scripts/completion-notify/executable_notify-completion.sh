#!/bin/bash
# Codex CLI Stop hook で完了通知を送信する。

set -euo pipefail

cd "$(dirname "$0")" || exit 1
# shellcheck source=/dev/null
source ./.env

INPUT_JSON=$(cat 2>/dev/null || true)
CONTINUE_JSON='{"continue":true}'
CONTINUE_EMITTED=0

# shellcheck disable=SC2317
emit_continue() {
    if [[ "$CONTINUE_EMITTED" -eq 0 ]]; then
        printf '%s\n' "$CONTINUE_JSON"
        CONTINUE_EMITTED=1
    fi
}
trap emit_continue EXIT

extract_json_field() {
    local jq_filter="$1"

    if [[ -z "$INPUT_JSON" ]]; then
        return 0
    fi

    printf '%s' "$INPUT_JSON" \
        | jq -re "${jq_filter} // empty" 2>/dev/null || true
}

append_field() {
    local fields_json="$1"
    local name="$2"
    local value="$3"
    local inline="$4"

    printf '%s' "$fields_json" \
        | jq --arg name "$name" --arg value "$value" --argjson inline "$inline" \
            '. + [{"name": $name, "value": $value, "inline": $inline}]'
}

if [[ -z "${DISCORD_WEBHOOK_URL:-}" ]]; then
    exit 0
fi

SESSION_ID=$(extract_json_field '.session_id')
CWD_PATH=$(extract_json_field '.cwd')
MODEL_NAME=$(extract_json_field '.model')
LAST_ASSISTANT_MESSAGE=$(extract_json_field '.last_assistant_message')

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")
MACHINE_NAME=$(hostname)

FIELDS='[]'
if ! FIELDS=$(append_field "$FIELDS" "📁 実行ディレクトリ" "$CWD_PATH" true); then
    exit 0
fi
if ! FIELDS=$(append_field "$FIELDS" "🆔 セッション ID" "$SESSION_ID" true); then
    exit 0
fi
if ! FIELDS=$(append_field "$FIELDS" "🧠 モデル" "$MODEL_NAME" true); then
    exit 0
fi

if [[ -n "$LAST_ASSISTANT_MESSAGE" ]]; then
    if ! FIELDS=$(append_field "$FIELDS" "🤖 最新の応答" "$LAST_ASSISTANT_MESSAGE" false); then
        exit 0
    fi
fi

CONTENT="Codex CLI Finished (${MACHINE_NAME})"
if [[ -n "${MENTION_USER_ID:-}" ]]; then
    CONTENT="<@${MENTION_USER_ID}> ${CONTENT}"
fi

if ! PAYLOAD=$(jq -n \
    --arg content "$CONTENT" \
    --arg timestamp "$TIMESTAMP" \
    --argjson fields "$FIELDS" \
    '{
      content: $content,
      embeds: [{
        title: "Codex CLI セッション完了",
        color: 5763719,
        timestamp: $timestamp,
        fields: $fields
      }]
    }'); then
    exit 0
fi

printf '%s\n' "$PAYLOAD" | "$(dirname "$0")/send-discord-notification.sh" >/dev/null 2>&1 &
exit 0
