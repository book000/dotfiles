#!/usr/bin/env bash
# rtk-hook-version: 6
# RTK Claude Code hook — rewrites commands to use rtk for token savings.
# Requires: rtk >= 0.23.0, jq
#
# This is a thin delegating hook: all rewrite logic lives in `rtk rewrite`,
# which is the single source of truth (src/discover/registry.rs).
# To add or change rewrite rules, edit the Rust registry — not this file.
#
# Exit code protocol for `rtk rewrite`:
#   0 + stdout  Rewrite found, no deny/ask rule matched → auto-allow
#   1           No RTK equivalent → pass through unchanged
#   2           Deny rule matched → pass through (Claude Code native deny handles it)
#   3 + stdout  Ask rule matched → rewrite but let Claude Code prompt the user

if ! command -v jq &>/dev/null; then
  echo "[rtk] WARNING: jq is not installed. Hook cannot rewrite commands. Install jq: https://jqlang.github.io/jq/download/" >&2
  exit 0
fi

if ! command -v rtk &>/dev/null; then
  echo "[rtk] WARNING: rtk is not installed or not in PATH. Hook cannot rewrite commands. Install: https://github.com/rtk-ai/rtk#installation" >&2
  exit 0
fi

# Version guard: rtk rewrite was added in 0.23.0.
# Older binaries: warn once and exit cleanly (no silent failure).
RTK_VERSION=$(rtk --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
if [ -n "$RTK_VERSION" ]; then
  MAJOR=$(echo "$RTK_VERSION" | cut -d. -f1)
  MINOR=$(echo "$RTK_VERSION" | cut -d. -f2)
  # Require >= 0.23.0
  if [ "$MAJOR" -eq 0 ] && [ "$MINOR" -lt 23 ]; then
    echo "[rtk] WARNING: rtk $RTK_VERSION is too old (need >= 0.23.0). Upgrade: cargo install rtk" >&2
    exit 0
  fi
fi

INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')

if [ -z "$CMD" ]; then
  exit 0
fi

# Delegate all rewrite + permission logic to the Rust binary.
REWRITTEN=$(rtk rewrite "$CMD" 2>/dev/null)
EXIT_CODE=$?

# Claude Code の worktree isolation 下では、rtk が挿入する git launcher
# (`rtk git ...`) を実行コマンドとして採用すると worktree スコープを
# 静的に証明できず拒否ループになる。EnterWorktree が作る worktree は
# `.claude/worktrees/` 配下に置かれる
# (home/dot_claude/hooks/executable_trust-worktree-cwd.sh と同じ規約) ため、
# それを cwd から検出し、git launcher が新規に導入された場合だけ compound
# command 全体を元の $CMD に巻き戻す。`rtk git` の部分文字列置換では、
# クォート文字列リテラルにたまたま `rtk git` という文字列が含まれるケース
# (例: echo "rtk git status") まで書き換えてコマンドの意味を変えてしまうため
# 採用しない。代わりに CMD と REWRITTEN それぞれに含まれる `rtk git` の
# 出現回数を比較し、増えていれば新規導入とみなす。増えていなければ
# (クォート内の文字列がそのまま残っているだけ、または git 呼び出し自体が
# 無い場合) rewrite をそのまま採用する。全体巻き戻しにより同じ compound
# command 内の他の rewrite (例: rtk ls) は犠牲になるが、正しさを優先する
# Phase 1 では妥当なトレードオフとする。deny/ask 判定 (EXIT_CODE) は
# rtk 側の結果をそのまま使い続けるため、安全網自体は失わない。
ADOPTED_CMD="$REWRITTEN"
if [[ "$CWD" == */.claude/worktrees/* ]]; then
  COUNT_CMD=$(grep -o -F 'rtk git' <<< "$CMD" | wc -l)
  COUNT_REWRITTEN=$(grep -o -F 'rtk git' <<< "$REWRITTEN" | wc -l)
  if [ "$COUNT_REWRITTEN" -gt "$COUNT_CMD" ]; then
    ADOPTED_CMD="$CMD"
  fi
  # worktree 内では rtk launcher の glob・展開・クォート・%{ 引数が組み込みガードに拒否されるため巻き戻す。
  # launcher 区間外のクォートは対象外。
  RISKY_LAUNCHER_RE='(^|[;&|][[:space:]]*)rtk [a-z-]+[^;&|]*([*?$`"'"'"']|%\{)'
  if grep -qE "$RISKY_LAUNCHER_RE" <<< "$REWRITTEN"; then
    ADOPTED_CMD="$CMD"
  fi
fi

case $EXIT_CODE in
  0)
    # Rewrite found, no permission rules matched — safe to auto-allow.
    # If the output is identical, the command was already using RTK
    # (worktree 内で git だけ戻した結果が CMD と一致する場合も含む)。
    [ "$CMD" = "$ADOPTED_CMD" ] && exit 0
    ;;
  1)
    # No RTK equivalent — pass through unchanged.
    exit 0
    ;;
  2)
    # Deny rule matched — let Claude Code's native deny rule handle it.
    exit 0
    ;;
  3)
    # Ask rule matched — rewrite the command but do NOT auto-allow so that
    # Claude Code prompts the user for confirmation.
    ;;
  *)
    exit 0
    ;;
esac

ORIGINAL_INPUT=$(echo "$INPUT" | jq -c '.tool_input')
UPDATED_INPUT=$(echo "$ORIGINAL_INPUT" | jq --arg cmd "$ADOPTED_CMD" '.command = $cmd')

if [ "$EXIT_CODE" -eq 3 ]; then
  # Ask: rewrite the command, omit permissionDecision so Claude Code prompts.
  jq -n \
    --argjson updated "$UPDATED_INPUT" \
    '{
      "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "updatedInput": $updated
      }
    }'
else
  # Allow: rewrite the command and auto-allow.
  jq -n \
    --argjson updated "$UPDATED_INPUT" \
    '{
      "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "allow",
        "permissionDecisionReason": "RTK auto-rewrite",
        "updatedInput": $updated
      }
    }'
fi
