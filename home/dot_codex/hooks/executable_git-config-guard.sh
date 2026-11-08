#!/bin/bash
# Block git config writes before Codex runs a Bash tool call.
# The analysis lives in git-config-guard-lib.sh next to this script.

set -euo pipefail

if ! command -v jq >/dev/null 2>&1; then
    echo "[git-config-guard] WARNING: jq is not installed. Hook cannot inspect commands, allowing." >&2
    exit 0
fi

INPUT=$(cat)
# Cheap pre-filter on the raw JSON: only "config" is checked (git may be hidden behind a variable),
# after dropping quotes and backslashes so that con""fig style splitting cannot bypass it.
# Inputs with a \u escape skip the filter: they are judged on the jq-decoded command.
INPUT_FLAT=${INPUT//[\\\"\']/}
if [[ "$INPUT_FLAT" != *config* && "$INPUT" != *'\u'* ]]; then
    exit 0
fi

CMD=$(jq -r '.tool_input.command? // empty' <<<"$INPUT")
# Words spelled with JSON \uXXXX escapes only appear after jq decodes them, so check again.
CMD_FLAT=${CMD//[\\\"\']/}
if [[ -z "$CMD" || "$CMD_FLAT" != *config* ]]; then
    exit 0
fi

deny() {
    jq -n \
        --arg reason "$1" \
        '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $reason}}'
    exit 0
}

# 字句解析は入力が大きいと二乗で遅くなる。フックのタイムアウトで素通しにならないよう、
# 別プロセスで時間を制限して実行し、時間切れや異常終了は拒否として扱う。
CWD=$(jq -r '.cwd? // empty' <<<"$INPUT")
RC=0
# shellcheck disable=SC2016
printf '%s' "$CMD" | timeout 5 bash -c 'source "$1" 2>/dev/null || exit 97; CMD=$(cat); gcg_denies "$CMD" "$2"' _ "${BASH_SOURCE[0]%/*}/git-config-guard-lib.sh" "$CWD" || RC=$?
case $RC in
1) exit 0 ;;
0) deny "git config writes are blocked by policy; ask the user to run this manually" ;;
97) deny "git-config-guard-lib.sh is missing next to git-config-guard.sh; run chezmoi apply" ;;
*) deny "git config analysis failed or timed out (exit $RC); split the command or ask the user to run it manually" ;;
esac
