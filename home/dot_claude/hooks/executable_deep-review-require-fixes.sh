#!/bin/bash

# Stop hook: block session end if deep-review found unresolved high-score issues.
# Triggers when /deep-review was run in this session and Score: 50+ findings remain.

# Read JSON from stdin (official hook contract: stdin JSON)
INPUT=$(cat)

# Get transcript path from stdin JSON
TRANSCRIPT_PATH=$(printf '%s' "$INPUT" | jq -r '.transcript_path // ""' 2>/dev/null || echo "")

# transcript ファイルが存在しない場合はブロックしない
if [[ -z "$TRANSCRIPT_PATH" ]] || [[ ! -f "$TRANSCRIPT_PATH" ]]; then
    echo '{}'
    exit 0
fi

# deep-review スキルの実行有無を確認する
if ! grep -q 'deep-review' "$TRANSCRIPT_PATH"; then
    echo '{}'
    exit 0
fi

# 最後の deep-review 実行以降のスコアのみを対象にする
# これにより、過去のセッションで修正済みの指摘が残り続けてブロックし続けることを防ぐ
LAST_LINE=$(grep -n 'deep-review' "$TRANSCRIPT_PATH" | tail -1 | cut -d: -f1)
if [[ -n "$LAST_LINE" ]]; then
    SCORES=$(tail -n "+$LAST_LINE" "$TRANSCRIPT_PATH" | grep -oP 'Score:\s*\K\d+' 2>/dev/null || echo "")
else
    SCORES=""
fi

# スコア 50 以上の指摘をカウントする
HIGH_SCORE_COUNT=0
MAX_SCORE=0
while IFS= read -r score; do
    if [[ -n "$score" && "$score" -ge 50 ]]; then
        HIGH_SCORE_COUNT=$((HIGH_SCORE_COUNT + 1))
        if [[ "$score" -gt "$MAX_SCORE" ]]; then
            MAX_SCORE="$score"
        fi
    fi
done <<< "$SCORES"

# スコア 50 以上の指摘が残っている場合はセッション終了をブロックする
if [[ "$HIGH_SCORE_COUNT" -gt 0 ]]; then
    REASON="⚠️ deep-review で ${HIGH_SCORE_COUNT} 件の重要な指摘事項が見つかりました（最高スコア: ${MAX_SCORE}）。

CLAUDE.md のルールに従い、スコア 50 以上の指摘事項に対応してから終了してください。

対応が必要な理由:
- スコア 50 以上の指摘は、機能や品質に直接影響する重要な問題です。
- これらの問題を放置すると、後で重大なバグや保守性の低下につながる可能性があります。

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
echo '{}'
exit 0
