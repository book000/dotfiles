#!/usr/bin/env node

const fs = require('fs');

// 環境変数から transcript パスを取得
const transcriptPath = process.env.TRANSCRIPT_PATH || '';

try {
  if (!transcriptPath || !fs.existsSync(transcriptPath)) {
    console.log(JSON.stringify({ block: false }));
    process.exit(0);
  }

  // transcript を読み込み
  const transcriptStr = fs.readFileSync(transcriptPath, 'utf-8');

  // コードレビュー実施チェック
  const hasCodeReview = transcriptStr.includes('/code-review:code-review');

  if (!hasCodeReview) {
    // コードレビュー未実施の場合はブロックしない
    console.log(JSON.stringify({ block: false }));
    process.exit(0);
  }

  // スコアを抽出
  const scoreMatches = transcriptStr.matchAll(/Score:\s*(\d+)/g);
  const scores = Array.from(scoreMatches, match => parseInt(match[1]));
  const highScoreIssues = scores.filter(score => score >= 50);

  if (highScoreIssues.length > 0) {
    const maxScore = Math.max(...highScoreIssues);
    console.log(JSON.stringify({
      block: true,
      message: `⚠️ **コードレビューで ${highScoreIssues.length} 件の重要な指摘事項が見つかりました**（最高スコア: ${maxScore}）\n\nCLAUDE.md のルールに従い、**スコア 50 以上の指摘事項**に対して必ず対応してから終了してください。\n\n## 対応が必要な理由\n\n- スコア 50 以上の指摘は、機能や品質に直接影響する重要な問題です\n- これらの問題を放置すると、後で重大なバグや保守性の低下につながる可能性があります\n\n## 対応手順\n\n1. スコア 50 以上の指摘をすべて確認\n2. 各指摘に対して適切な修正を実施（不明点があれば Codex CLI に相談）\n3. 修正内容をコミット・プッシュ\n4. PR 本文を更新\n5. 必要に応じて再度コードレビューを実施`
    }));
    process.exit(0);
  }

  // スコア 50 未満のみ、または指摘なしの場合はブロックしない
  console.log(JSON.stringify({ block: false }));
} catch (error) {
  // エラーが発生した場合はブロックしない
  console.error('Error in require-code-review-fixes hook:', error);
  console.log(JSON.stringify({ block: false }));
  process.exit(0);
}
