#!/bin/bash
# EnterWorktree の PostToolUse フックスクリプト。
# フック入力 JSON の cwd (EnterWorktree 実行後の新しい作業ディレクトリ) を
# Claude Code のワークスペース信頼済みディレクトリとして ~/.claude.json に登録する。
# EnterWorktree はシェルラッパー (claude コマンド) 経由で起動されないため、
# 90-ai-alias.zsh/sh の _claude_trust_cwd() が実行されず、
# Workspace Trust dialog が発生する問題 (Issue #166) への対策。

command -v jq > /dev/null 2>&1 || exit 0

INPUT_JSON=$(cat)
CWD=$(echo "$INPUT_JSON" | jq -r '.cwd // empty' 2> /dev/null)

[ -n "$CWD" ] || exit 0

CONFIG="$HOME/.claude.json"
[ -f "$CONFIG" ] || exit 0

if [ "$(jq -r --arg p "$CWD" '.projects[$p].hasTrustDialogAccepted // false' "$CONFIG" 2> /dev/null)" != "true" ]; then
    TMP=$(mktemp "${CONFIG}.XXXXXX") || exit 0
    # 元ファイルのパーミッションを一時ファイルに反映する (GNU stat / BSD stat の両方に対応)
    PERM=$(stat -c '%a' "$CONFIG" 2> /dev/null || stat -f '%Lp' "$CONFIG" 2> /dev/null)
    [ -n "$PERM" ] && chmod "$PERM" "$TMP"
    if jq --arg p "$CWD" '.projects[$p] = ((.projects[$p] // {}) + {hasTrustDialogAccepted: true})' "$CONFIG" > "$TMP"; then
        mv "$TMP" "$CONFIG" || rm -f "$TMP"
    else
        rm -f "$TMP"
    fi
fi

exit 0
