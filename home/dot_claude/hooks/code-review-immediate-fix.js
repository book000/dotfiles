#!/usr/bin/env node

// 環境変数から toolResult を取得
const toolName = process.env.TOOL_NAME || '';
const toolInput = process.env.TOOL_INPUT || '{}';
const toolResult = process.env.TOOL_RESULT || '';

try {
  // toolInput をパース
  const input = JSON.parse(toolInput);

  // code-review:code-review スキル以外はスキップ
  if (input.skill !== 'code-review:code-review') {
    console.log(JSON.stringify({ block: false }));
    process.exit(0);
  }

  // toolResult を文字列に変換
  const resultStr = String(toolResult);

  // スコアを抽出
  const scoreMatches = resultStr.matchAll(/Score:\s*(\d+)/g);
  const scores = Array.from(scoreMatches, match => parseInt(match[1]));
  const highScoreIssues = scores.filter(score => score >= 50);

  if (highScoreIssues.length > 0) {
    const maxScore = Math.max(...highScoreIssues);
    console.log(JSON.stringify({
      block: true,
      message: `🔔 **コードレビューで ${highScoreIssues.length} 件の重要な指摘事項が見つかりました**（最高スコア: ${maxScore}）\n\nCLAUDE.md の規則により、**スコア 50 以上の指摘事項**に対して必ず対応してください。\n\n## 対応手順\n\n1. スコア 50 以上の指摘をすべて確認\n2. 各指摘に対して適切な修正を実施（不明点があれば Codex CLI に相談）\n3. 修正内容をコミット・プッシュ\n4. PR 本文を更新\n5. 必要に応じて再度コードレビューを実施\n\n⚠️ **重要**: 指摘事項への対応を完了してから次に進んでください。対応漏れは禁止されています。`
    }));
    process.exit(0);
  }

  // スコア 50 未満の場合はリマインダー
  if (scores.length > 0) {
    console.log(JSON.stringify({
      block: false,
      message: `ℹ️ コードレビューで ${scores.length} 件の指摘事項が見つかりました（すべてスコア 50 未満）。\n\n必要に応じて対応を検討してください。`
    }));
    process.exit(0);
  }

  // スコア情報がない場合は "Found X issue(s)" から判定
  const totalIssueMatch = resultStr.match(/Found (\d+) issues?/);
  if (totalIssueMatch) {
    const totalIssues = parseInt(totalIssueMatch[1]);
    if (totalIssues > 0) {
      console.log(JSON.stringify({
        block: false,
        message: `ℹ️ コードレビューで ${totalIssues} 件の指摘事項が見つかりました（スコア情報なし）。\n\n必要に応じて対応を検討してください。`
      }));
      process.exit(0);
    }
  }

  // 問題なし
  console.log(JSON.stringify({ block: false }));
} catch (error) {
  // エラーが発生した場合はブロックしない
  console.error('Error in code-review-immediate-fix hook:', error);
  console.log(JSON.stringify({ block: false }));
  process.exit(0);
}
