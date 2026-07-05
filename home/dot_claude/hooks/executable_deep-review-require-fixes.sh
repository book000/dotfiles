#!/bin/bash

# Stop hook: セッション終了時に deep-review の未対応指摘が残っていないか検証する。
# トランスクリプトのテキストパースには頼らず、PostToolUse フックが書き出した
# ステートファイル (~/.claude/data/deep-review-state.json) を優先参照する。
# ステートファイルが存在しない場合はブロックしない（セッション内で deep-review 未実行）。

STATE_FILE="$HOME/.claude/data/deep-review-state.json"

# stdin から JSON を読み込む（公式フック契約: stdin JSON）
INPUT=$(cat)

# 現在のセッション ID を取得する
SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // ""' 2>/dev/null)

# ステートファイルが存在しない → このセッションで deep-review 未実行 → ブロックしない
if [[ ! -f "$STATE_FILE" ]]; then
    exit 0
fi

# ステートファイルを読み込む
STATE_SESSION=$(jq -r '.session_id // ""' "$STATE_FILE" 2>/dev/null)
STATE_TIMESTAMP=$(jq -r '.timestamp // 0' "$STATE_FILE" 2>/dev/null)
HIGH_SCORE_COUNT=$(jq -r '.high_score_count // 0' "$STATE_FILE" 2>/dev/null)
MAX_SCORE=$(jq -r '.max_score // 0' "$STATE_FILE" 2>/dev/null)

# ステートファイルの有効期限（24時間）
STATE_TTL=86400
CURRENT_TIME=$(date +%s)
STATE_AGE=$(( CURRENT_TIME - STATE_TIMESTAMP ))

# セッション ID が一致しない、または SESSION_ID はあるのに STATE_SESSION が
# 空（旧形式ファイル、他セッション由来の可能性あり）の場合は信頼しない
if [[ -n "$SESSION_ID" && "$SESSION_ID" != "$STATE_SESSION" ]]; then
    exit 0
fi

# ここに到達するのは、SESSION_ID が一致した場合、または SESSION_ID 自体が
# 空（stdin から取得できなかった後方互換ケース）の場合のみ。TTL で判定する
if [[ "$STATE_AGE" -gt "$STATE_TTL" ]]; then
    exit 0
fi

# スコア 50 以上の指摘が残っている場合はセッション終了をブロックする
if [[ "$HIGH_SCORE_COUNT" -gt 0 ]]; then
    REASON="⚠️ deep-review で ${HIGH_SCORE_COUNT} 件の重要な指摘事項が見つかりました（最高スコア: ${MAX_SCORE}）。

CLAUDE.md のルールに従い、スコア 50 以上の指摘事項に対応してから終了してください。

対応手順:
1. スコア 50 以上の指摘をすべて確認する
2. 各指摘に対して適切な修正を実施する
3. 修正内容をコミット・プッシュする
4. PR 本文を更新する
5. 必要に応じて再度 /deep-review を実施する"
    jq -n --arg reason "$REASON" '{"decision":"block","reason":$reason}'
    exit 0
fi

# 対応済みまたは指摘なし
exit 0
