#!/bin/bash
# Block git config writes before Codex runs a Bash tool call.

set -euo pipefail

if ! command -v jq >/dev/null 2>&1; then
    echo "[git-config-guard] WARNING: jq is not installed. Hook cannot inspect commands, allowing." >&2
    exit 0
fi

INPUT=$(cat)
# JSON の \uXXXX で綴った語は jq でデコードして初めて "git config" になるため、
# \u を含む入力は足切りせずデコード後の $CMD で判定する。
if [[ "$INPUT" != *"git config"* && "$INPUT" != *'\u'* ]]; then
    exit 0
fi

CMD=$(jq -r '.tool_input.command? // empty' <<<"$INPUT")
if [[ -z "$CMD" || "$CMD" != *"git config"* ]]; then
    exit 0
fi

IFS=$'\n' read -rd '' -a SEGMENTS < <(printf '%s\n' "$CMD" | sed -E 's/(&&|\|\||;|\|)/\n/g') || true

for SEGMENT in "${SEGMENTS[@]}"; do
    [[ "$SEGMENT" == *"git config"* ]] || continue

    if [[ "$SEGMENT" =~ --unset-all|--unset|--remove-section|--rename-section|--edit|(^|[[:space:]])-e([[:space:]]|$) ]]; then
        DENY=1
    else
        AFTER_CONFIG=$(sed -E 's/^.*git[[:space:]]+config[[:space:]]*//' <<<"$SEGMENT")
        read -ra ARGS <<<"$AFTER_CONFIG"
        POSITIONAL_COUNT=0
        for arg in "${ARGS[@]}"; do
            [[ "$arg" == -* ]] && continue
            POSITIONAL_COUNT=$((POSITIONAL_COUNT + 1))
        done
        [[ "$POSITIONAL_COUNT" -ge 2 ]] && DENY=1 || DENY=0
    fi

    if [[ "$DENY" -eq 1 ]]; then
        jq -n \
            --arg reason "git config writes are blocked by policy; ask the user to run this manually" \
            '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $reason}}'
        exit 0
    fi
done
