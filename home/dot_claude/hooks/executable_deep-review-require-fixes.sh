#!/bin/bash

# Stop hook: セッション終了時に deep-review / lite-review の未対応指摘が残っていないか検証する。
# deep-review / lite-review は ledger (ledger.sh が書き込む) を直接読んで判定する。
# fix モードで open な merge-blocker が残っている場合のみブロックし、ledger がない場合はブロックしない。

STATE_DIR="$HOME/.claude/data"

# stdin から JSON を読み込む（公式フック契約: stdin JSON）
INPUT=$(cat)

# バックグラウンドのサブエージェントが動作中なら修正中とみなしブロックしない（終了後の次の Stop で再判定する）。
# monitor 等は常駐し得るため対象にしない
if [[ "$(printf '%s' "$INPUT" | jq -r '[.background_tasks[]? | select(.type == "subagent")] | length' 2>/dev/null)" =~ ^[1-9][0-9]*$ ]]; then
    exit 0
fi

# 現在のセッション ID を取得する
SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // ""' 2>/dev/null)

# deep-review / lite-review は ledger を直接読んで判定する。fix モードで open な merge-blocker が残っている場合のみブロックする。
# ledger なし・schema/session 不一致・TTL 超過・破損は非ブロック。
if [[ "$SESSION_ID" =~ ^[A-Za-z0-9_-]+$ ]]; then
    LEDGER="${DEEP_REVIEW_DATA_DIR:-$STATE_DIR}/deep-review-ledger-${SESSION_ID}.json"
    if [[ -f "$LEDGER" ]]; then
        if COUNT=$(jq -r --arg s "$SESSION_ID" '
            if .schema_version == 1 and .session_id == $s and (now - .updated_at) <= 86400 and .mode == "fix"
            then [.findings[] | select(.class == "merge-blocker" and .status == "open")] | length
            else 0 end' "$LEDGER" 2>/dev/null); then
            if [[ "$COUNT" -gt 0 ]]; then
                REASON="⚠️ review (fix モード) で ${COUNT} 件の未解決のマージ前必須指摘が残っています。

対応手順:
1. ledger の open な merge-blocker 指摘をすべて確認する
2. 各指摘を修正して検証し、ledger.sh で status を fixed / false_positive / deferred に更新する
3. 修正内容をコミット・プッシュする
4. PR が存在する場合は PR 本文を更新する"
                jq -n --arg reason "$REASON" '{"decision":"block","reason":$reason}'
                exit 0
            fi
        else
            echo "WARNING: corrupted deep-review ledger: $LEDGER" >&2
        fi
    fi
fi

exit 0
