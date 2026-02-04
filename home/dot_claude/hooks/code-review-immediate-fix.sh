#!/bin/bash

# 環境変数から toolInput を取得
TOOL_INPUT="${TOOL_INPUT:-{}}"
TOOL_RESULT="${TOOL_RESULT:-}"

# toolInput から skill をパース
SKILL=$(printf '%s' "$TOOL_INPUT" | jq -r '.skill // ""' 2>/dev/null || echo "")

# code-review:code-review スキル以外はスキップ
if [[ "$SKILL" != "code-review:code-review" ]]; then
  echo '{"block":false}'
  exit 0
fi

# toolResult からスコアを抽出
SCORES=$(echo "$TOOL_RESULT" | grep -oP 'Score:\s*\K\d+' || echo "")

# スコア 50 以上の指摘をフィルタリング
HIGH_SCORES=()
MAX_SCORE=0
while IFS= read -r score; do
  if [[ -n "$score" && "$score" -ge 50 ]]; then
    HIGH_SCORES+=("$score")
    if [[ "$score" -gt "$MAX_SCORE" ]]; then
      MAX_SCORE="$score"
    fi
  fi
done <<< "$SCORES"

# スコア 50 以上の指摘がある場合
if [[ ${#HIGH_SCORES[@]} -gt 0 ]]; then
  MESSAGE="🔔 **コードレビューで ${#HIGH_SCORES[@]} 件の重要な指摘事項が見つかりました**（最高スコア: $MAX_SCORE）\n\nCLAUDE.md の規則により、**スコア 50 以上の指摘事項**に対して必ず対応してください。\n\n## 対応手順\n\n1. スコア 50 以上の指摘をすべて確認\n2. 各指摘に対して適切な修正を実施（不明点があれば Codex CLI に相談）\n3. 修正内容をコミット・プッシュ\n4. PR 本文を更新\n5. 必要に応じて再度コードレビューを実施\n\n⚠️ **重要**: 指摘事項への対応を完了してから次に進んでください。対応漏れは禁止されています。"
  jq -n --arg msg "$MESSAGE" '{"block":true,"message":$msg}'
  exit 0
fi

# スコア情報がある場合（すべて 50 未満）
if [[ -n "$SCORES" ]]; then
  TOTAL_SCORES=$(echo "$SCORES" | wc -l)
  MESSAGE="ℹ️ コードレビューで $TOTAL_SCORES 件の指摘事項が見つかりました（すべてスコア 50 未満）。\n\n必要に応じて対応を検討してください。"
  jq -n --arg msg "$MESSAGE" '{"block":false,"message":$msg}'
  exit 0
fi

# スコア情報がない場合は "Found X issue(s)" から判定
TOTAL_ISSUES=$(echo "$TOOL_RESULT" | grep -oP 'Found \K\d+(?= issues?)' || echo "")
if [[ -n "$TOTAL_ISSUES" && "$TOTAL_ISSUES" -gt 0 ]]; then
  MESSAGE="ℹ️ コードレビューで $TOTAL_ISSUES 件の指摘事項が見つかりました（スコア情報なし）。\n\n必要に応じて対応を検討してください。"
  jq -n --arg msg "$MESSAGE" '{"block":false,"message":$msg}'
  exit 0
fi

# 問題なし
echo '{"block":false}'
