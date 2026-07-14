#!/bin/bash
# git config の書き込み系操作をブロックする PreToolUse フック。
# permission mode (通常 / skip-permissions) に関わらず必ず実行されるため、
# これを「git config 書き込みを防ぐ唯一の確実な強制手段」として扱う。
#
# 判定ルール:
#   - コマンドに "git config" を含まない → 対象外、常に許可
#   - 読み取り系 (--get/--get-all/--get-regexp/--get-urlmatch/--list/-l、
#     または値引数を伴わない参照呼び出し) → 常に許可
#   - それ以外(書き込み・削除。--unset/--unset-all/--remove-section/
#     --rename-section/--edit/-e を含む) → デフォルト拒否
#
# 既知の制限: 素直な "git config ..." 形式のみ検出する。
# "git -C <dir> config" や "git --git-dir=... config" のような
# 変則的な前置形式、alias・変数展開経由の呼び出しは対象外。

# 将来の例外を許すための allow-list(現時点では空)。
# 一致した場合は書き込み系であっても常に許可する。
ALLOWLIST=()

if ! command -v jq &> /dev/null; then
    echo "[git-config-guard] WARNING: jq is not installed. Hook cannot inspect commands, allowing." >&2
    exit 0
fi

INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

[ -n "$CMD" ] || exit 0

# "git config" を含まないコマンドは対象外
if [[ "$CMD" != *"git config"* ]]; then
    exit 0
fi

# allow-list に一致すれば常に許可
for pattern in "${ALLOWLIST[@]}"; do
    if [[ "$CMD" == *"$pattern"* ]]; then
        exit 0
    fi
done

# 読み取り専用オプションが含まれていれば許可
if [[ "$CMD" =~ --get-all|--get-regexp|--get-urlmatch|--get|--list|(^|[[:space:]])-l([[:space:]]|$) ]]; then
    exit 0
fi

# 書き込み・削除系オプションが明示されていなければ、位置引数の個数で
# 「値を指定しない参照呼び出し」かどうかを判定する。
if [[ ! "$CMD" =~ --unset-all|--unset|--remove-section|--rename-section|--edit|(^|[[:space:]])-e([[:space:]]|$) ]]; then
    AFTER_CONFIG=$(echo "$CMD" | sed -E 's/^.*git[[:space:]]+config[[:space:]]*//')
    read -ra ARGS <<< "$AFTER_CONFIG"
    POSITIONAL_COUNT=0
    for arg in "${ARGS[@]}"; do
        [[ "$arg" == -* ]] && continue
        POSITIONAL_COUNT=$((POSITIONAL_COUNT + 1))
    done
    # 位置引数 (オプションを除いた実引数) が1個以下 → キー名のみの参照呼び出し
    if [ "$POSITIONAL_COUNT" -le 1 ]; then
        exit 0
    fi
fi

jq -n \
    --arg reason "git config writes are blocked by policy; ask the user to run this manually" \
    '{
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": $reason
        }
    }'
