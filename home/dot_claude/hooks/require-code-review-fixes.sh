#!/bin/bash

# 環境変数から transcript パスを取得
TRANSCRIPT_PATH="${TRANSCRIPT_PATH:-}"

# transcript ファイルが存在しない場合
if [[ ! -f "$TRANSCRIPT_PATH" ]]; then
  echo '{"block":false}'
  exit 0
fi

# transcript を読み込み
TRANSCRIPT=$(cat "$TRANSCRIPT_PATH")

# コードレビュー実施チェック
if ! echo "$TRANSCRIPT" | grep -q '/code-review:code-review'; then
  # コードレビュー未実施の場合はブロックしない
  echo '{"block":false}'
  exit 0
fi

# スコアを抽出
SCORES=$(echo "$TRANSCRIPT" | grep -oP 'Score:\s*\K\d+' || echo "")

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
  MESSAGE="⚠️ **コードレビューで ${#HIGH_SCORES[@]} 件の重要な指摘事項が見つかりました**（最高スコア: $MAX_SCORE）\n\nCLAUDE.md のルールに従い、**スコア 50 以上の指摘事項**に対して必ず対応してから終了してください。\n\n## 対応が必要な理由\n\n- スコア 50 以上の指摘は、機能や品質に直接影響する重要な問題です\n- これらの問題を放置すると、後で重大なバグや保守性の低下につながる可能性があります\n\n## 対応手順\n\n1. スコア 50 以上の指摘をすべて確認\n2. 各指摘に対して適切な修正を実施（不明点があれば Codex CLI に相談）\n3. 修正内容をコミット・プッシュ\n4. PR 本文を更新\n5. 必要に応じて再度コードレビューを実施"
  jq -n --arg msg "$MESSAGE" '{"block":true,"message":$msg}'
  exit 0
fi

# スコア 50 未満のみ、または指摘なしの場合はブロックしない
echo '{"block":false}'
