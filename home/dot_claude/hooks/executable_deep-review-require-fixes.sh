#!/bin/bash

# セッション終了時に deep-review の指摘対応漏れを防止する Stop フック
# /deep-review を実行済みでスコア 50 以上の指摘が残っている場合に終了をブロックする

# stdin から JSON を読み込む（公式フック契約: stdin JSON）
INPUT=$(cat)

# transcript パスを取得する（stdin JSON を優先し、環境変数にフォールバック）
TRANSCRIPT_PATH=$(printf '%s' "$INPUT" | jq -r '.transcript_path // ""' 2>/dev/null || echo "")
if [[ -z "$TRANSCRIPT_PATH" ]]; then
    TRANSCRIPT_PATH="${TRANSCRIPT_PATH:-}"
fi

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

# transcript からスコアを抽出する
SCORES=$(grep -oP 'Score:\s*\K\d+' "$TRANSCRIPT_PATH" 2>/dev/null || echo "")

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
