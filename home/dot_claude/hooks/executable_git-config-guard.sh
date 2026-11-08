#!/bin/bash
# git config の書き込み系操作をブロックする PreToolUse フック。
# permission mode に関わらず必ず実行されるため、書き込みを防ぐ唯一の確実な強制手段として扱う。
#
# 判定ロジックは同じディレクトリの git-config-guard-lib.sh にある。コマンド文字列を
# シェルの構文として解析し、コマンド位置の git config だけを対象にする。
# 位置引数(オプションを除く実引数)が2個以上ならフラグの内容に関わらず拒否する。

if ! command -v jq &> /dev/null; then
    echo "[git-config-guard] WARNING: jq is not installed. Hook cannot inspect commands, allowing." >&2
    exit 0
fi

INPUT=$(cat)

# jq 起動前に生の JSON 文字列上で足切りする(ホットパス最適化)。
# "git -C dir config" や $GIT config のように git が現れない形もあるため "config" だけを見る。
# JSON 中のクォートやバックスラッシュを除いて見るので、con""fig のような分割では回避できない。
# \u エスケープを含む入力は文字列を確定できないので足切りせず、jq のデコード後に判定する。
INPUT_FLAT=${INPUT//[\\\"\']/}
if [[ "$INPUT_FLAT" != *config* && "$INPUT" != *'\u'* ]]; then
    exit 0
fi

CMD=$(jq -r '.tool_input.command? // empty' <<< "$INPUT")

# JSON の \uXXXX で綴られた語は jq でデコードして初めて見えるため、デコード後にも確認する。
CMD_FLAT=${CMD//[\\\"\']/}
if [[ -z "$CMD" || "$CMD_FLAT" != *config* ]]; then
    exit 0
fi

deny() {
    jq -n \
        --arg reason "$1" \
        '{
            "hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "permissionDecision": "deny",
                "permissionDecisionReason": $reason
            }
        }'
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
