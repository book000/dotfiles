---
name: require-code-review-fixes
enabled: true
event: stop
action: |\n  // transcript を文字列に変換（型安全性の向上）\n  const transcriptStr = String(transcript || '');\n\n  // このセッションでコードレビューが実行されたかチェック\n  const hasCodeReview = transcriptStr.includes('/code-review:code-review');\n\n  if (!hasCodeReview) {\n    // コードレビュー未実施の場合はブロックしない（誤検知回避）\n    return { block: false };\n  }\n\n  // コードレビュー結果からスコアを抽出\n  const scoreMatches = transcriptStr.matchAll(/Score:\\s*(\\d+)/g);\n  const scores = Array.from(scoreMatches, match => parseInt(match[1]));\n  const highScoreIssues = scores.filter(score => score >= 50);\n\n  if (highScoreIssues.length > 0) {\n    const maxScore = Math.max(...highScoreIssues);\n    return {\n      block: true,\n      message: `⚠️ **コードレビューで ${highScoreIssues.length} 件の重要な指摘事項が見つかりました**（最高スコア: ${maxScore}）\\n\\nCLAUDE.md のルールに従い、**スコア 50 以上の指摘事項**に対して必ず対応してから終了してください。\\n\\n## 対応が必要な理由\\n\\n- スコア 50 以上の指摘は、機能や品質に直接影響する重要な問題です\\n- これらの問題を放置すると、後で重大なバグや保守性の低下につながる可能性があります\\n\\n## 次のステップ\\n\\n1. スコア 50 以上の指摘をすべて確認\\n2. 各指摘に対して適切な修正を実施\\n3. 修正内容をコミット・プッシュ\\n4. PR 本文を更新\\n5. 必要に応じて再度コードレビューを実施`\n    };\n  }\n\n  // スコア 50 未満のみ、または指摘なしの場合はブロックしない\n  return { block: false };
---

# コードレビュー対応漏れ防止（セッション終了時）

このルールは、セッション終了時にコードレビューでの指摘事項への対応漏れを防ぐためのものです。

## 改善内容

- **自動判定**: transcript を解析し、コードレビュー実施とスコア 50 以上の指摘を自動検出
- **誤検知回避**: コードレビュー未実施の場合はブロックしない
- **スコアベース**: スコア 50 以上の指摘がある場合のみブロック
- **詳細なメッセージ**: 対応が必要な理由と次のステップを明示

## 既存ルールとの違い

- `hookify.code-review-immediate-fix.local.md`: `event: PostToolUse` でコードレビュー実行直後にチェック
- このルール: `event: stop` でセッション終了時に最終確認

## 二重の安全網

このルールは、`hookify.code-review-immediate-fix.local.md` と組み合わせて二重の安全網を提供します：

1. **PostToolUse イベント**: コードレビュー実行直後に即座ブロック（スコア 50 以上の指摘がある場合）
2. **Stop イベント（このルール）**: セッション終了時に最終確認（自動判定）

これにより、セッション内およびセッション間での対応漏れを防ぎます。

## 動作

1. コードレビュー未実施の場合:
   - 処理をブロックしない（誤検知回避）

2. コードレビュー実施済みでスコア 50 以上の指摘がある場合:
   - 処理をブロック
   - 詳細な対応手順を表示
   - 最高スコアを表示

3. コードレビュー実施済みでスコア 50 未満の指摘のみの場合:
   - 処理をブロックしない
