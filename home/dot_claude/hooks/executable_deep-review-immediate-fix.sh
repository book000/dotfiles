#!/bin/bash

# deep-review スキル実行後に指摘事項の対応を促す PostToolUse フック
# スコア 50 以上の指摘が残っている場合に Claude の処理をブロックする

# stdin から JSON を読み込む（公式フック契約: stdin JSON）
INPUT=$(cat)

# Skill ツールの実行か確認する
TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null || echo "")
if [[ "$TOOL_NAME" != "Skill" ]]; then
    echo '{}'
    exit 0
fi

# deep-review スキル以外はスキップする
# skill_name と skill の両方を試みて互換性を確保する
SKILL=$(printf '%s' "$INPUT" | jq -r '.tool_input.skill_name // .tool_input.skill // ""' 2>/dev/null || echo "")
if [[ "$SKILL" != "deep-review" ]]; then
    echo '{}'
    exit 0
fi

# tool_response からスコアを抽出する
TOOL_RESPONSE=$(printf '%s' "$INPUT" | jq -r '.tool_response // ""' 2>/dev/null || echo "")
SCORES=$(printf '%s' "$TOOL_RESPONSE" | grep -oP 'Score:\s*\K\d+' 2>/dev/null || echo "")

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

# スコア 50 以上の指摘がある場合はブロックして対応を促す
if [[ "$HIGH_SCORE_COUNT" -gt 0 ]]; then
    REASON="🔔 deep-review で ${HIGH_SCORE_COUNT} 件の重要な指摘事項が見つかりました（最高スコア: ${MAX_SCORE}）。

CLAUDE.md の規則により、スコア 50 以上の指摘事項に必ず対応してください。

対応手順:
1. スコア 50 以上の指摘をすべて確認する
2. 各指摘に対して適切な修正を実施する
3. 修正内容をコミット・プッシュする
4. PR 本文を更新する
5. 必要に応じて再度 /deep-review を実施する

対応漏れは禁止されています。"
    jq -n --arg reason "$REASON" '{"decision":"block","reason":$reason}'
    exit 0
fi

# スコア情報はあるが全件 50 未満の場合
if [[ -n "$SCORES" ]]; then
    TOTAL=$(printf '%s' "$SCORES" | grep -c '^' 2>/dev/null || echo 0)
    jq -n --arg total "$TOTAL" '{"decision":"approve","reason":("deep-review: " + $total + " 件の指摘がありましたが、すべてスコア 50 未満です。")}'
    exit 0
fi

# スコア情報がない場合は "Found X issue(s)" 形式から件数を取得する
TOTAL_ISSUES=$(printf '%s' "$TOOL_RESPONSE" | grep -oP 'Found \K\d+(?= issues?)' 2>/dev/null || echo "")
if [[ -n "$TOTAL_ISSUES" && "$TOTAL_ISSUES" -gt 0 ]]; then
    jq -n --arg total "$TOTAL_ISSUES" '{"decision":"approve","reason":("deep-review: " + $total + " 件の指摘がありました（スコア情報なし）。必要に応じて対応を検討してください。")}'
    exit 0
fi

# 問題なし
echo '{}'
exit 0
