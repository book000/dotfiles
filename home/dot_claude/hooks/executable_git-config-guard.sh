#!/bin/bash
# git config の書き込み系操作をブロックする PreToolUse フック。
# permission mode に関わらず必ず実行されるため、書き込みを防ぐ唯一の確実な強制手段として扱う。
#
# コマンド文字列は &&/||/;/| で区切ったセグメントごとに判定する。全体を単一の
# 文字列として正規表現照合すると、連結された別コマンド側の読み取りオプションや
# 別の "git config" 文字列に引きずられて、実際の書き込みセグメントを見逃すため。
#
# 位置引数(オプションを除く実引数)が2個以上ならフラグの内容に関わらず拒否する。
# --get 等の読み取り系オプションを個別に判定すると、値の末尾に付与して分類を
# 偽装する回避策(例: git config user.name attacker --get x)を許してしまうため。
#
# 既知の制限: 素直な "git config ..." 形式のみ検出する。
# "git -C <dir> config" や "git --git-dir=... config" などの変則的な前置形式、
# alias・変数展開経由の呼び出しは対象外。

# 将来の例外を許す allow-list(現時点では空)。一致すれば書き込みでも常に許可する。
ALLOWLIST=()

if ! command -v jq &> /dev/null; then
    echo "[git-config-guard] WARNING: jq is not installed. Hook cannot inspect commands, allowing." >&2
    exit 0
fi

INPUT=$(cat)

# jq 起動前に生の JSON 文字列上で足切りする(ホットパス最適化)。
# command に "git config" を含まなければ JSON 文字列側にも含まれないため、
# 後続の $CMD に対する判定を弱めることはない。
if [[ "$INPUT" != *"git config"* ]]; then
    exit 0
fi

CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

if [[ -z "$CMD" || "$CMD" != *"git config"* ]]; then
    exit 0
fi

IFS=$'\n' read -rd '' -a SEGMENTS < <(printf '%s\n' "$CMD" | sed -E 's/(&&|\|\||;|\|)/\n/g') || true

DENY=0
for SEGMENT in "${SEGMENTS[@]}"; do
    [[ "$SEGMENT" == *"git config"* ]] || continue

    IS_ALLOWED=0
    for pattern in "${ALLOWLIST[@]}"; do
        if [[ "$SEGMENT" == *"$pattern"* ]]; then
            IS_ALLOWED=1
            break
        fi
    done
    [ "$IS_ALLOWED" -eq 1 ] && continue

    if [[ "$SEGMENT" =~ --unset-all|--unset|--remove-section|--rename-section|--edit|(^|[[:space:]])-e([[:space:]]|$) ]]; then
        DENY=1
        break
    fi

    AFTER_CONFIG=$(echo "$SEGMENT" | sed -E 's/^.*git[[:space:]]+config[[:space:]]*//')
    read -ra ARGS <<< "$AFTER_CONFIG"
    POSITIONAL_COUNT=0
    for arg in "${ARGS[@]}"; do
        [[ "$arg" == -* ]] && continue
        POSITIONAL_COUNT=$((POSITIONAL_COUNT + 1))
    done
    if [ "$POSITIONAL_COUNT" -ge 2 ]; then
        DENY=1
        break
    fi
done

[ "$DENY" -eq 1 ] || exit 0

jq -n \
    --arg reason "git config writes are blocked by policy; ask the user to run this manually" \
    '{
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": $reason
        }
    }'
