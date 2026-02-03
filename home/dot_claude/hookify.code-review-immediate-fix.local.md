---
name: code-review-immediate-fix
enabled: true
event: PostToolUse
tool: Skill
condition: |
  toolInput.skill === "code-review:code-review"
action: |
  // toolResult を文字列に変換（型安全性の向上）
  const resultStr = String(toolResult || '');

  // コードレビュー結果から指摘事項のスコアを抽出
  const scoreMatches = resultStr.matchAll(/Score:\s*(\d+)/g);
  const scores = Array.from(scoreMatches, match => parseInt(match[1]));
  const highScoreIssues = scores.filter(score => score >= 50);

  if (highScoreIssues.length > 0) {
    const maxScore = Math.max(...highScoreIssues);
    return {
      block: true,
      message: `🔔 **コードレビューで ${highScoreIssues.length} 件の重要な指摘事項が見つかりました**（最高スコア: ${maxScore}）\n\nCLAUDE.md の規則により、**スコア 50 以上の指摘事項**に対して必ず対応してください。\n\n## 対応手順\n\n1. スコア 50 以上の指摘をすべて確認\n2. 各指摘に対して適切な修正を実施（不明点があれば Codex CLI に相談）\n3. 修正内容をコミット・プッシュ\n4. PR 本文を更新\n5. 必要に応じて再度コードレビューを実施\n\n⚠️ **重要**: 指摘事項への対応を完了してから次に進んでください。対応漏れは禁止されています。`
    };
  }

  // スコア 50 未満の指摘のみの場合はリマインダーのみ表示
  // フォールバック: scores がある場合はそれを使用
  if (scores.length > 0) {
    return {
      block: false,
      message: `ℹ️ コードレビューで ${scores.length} 件の指摘事項が見つかりました（すべてスコア 50 未満）。\n\n必要に応じて対応を検討してください。`
    };
  }

  // scores がない場合は "Found X issue(s)" から判定
  const totalIssueMatch = resultStr.match(/Found (\d+) issues?/);
  if (totalIssueMatch) {
    const totalIssues = parseInt(totalIssueMatch[1]);
    if (totalIssues > 0) {
      return {
        block: false,
        message: `ℹ️ コードレビューで ${totalIssues} 件の指摘事項が見つかりました（スコア情報なし）。\n\n必要に応じて対応を検討してください。`
      };
    }
  }

  // スコア情報も issue 情報も見つからない場合はブロックしない
  return {
    block: false
  };
---

# コードレビュー直後の修正を促す

このルールは、`/code-review:code-review` スキル実行直後に指摘事項が見つかった場合、即座に修正を促すためのものです。

## 改善内容

- スコアベースの判定: スコア 50 以上の指摘のみブロック
- 詳細なリマインダー: 次のステップを明確に表示
- スコア 50 未満の指摘: リマインダーのみ表示（ブロックしない）
- 型安全性の向上: `toolResult` を文字列に変換してから処理
- 正規表現の改善: `issue` と `issues` の両方に対応

## 既存ルールとの違い

- `hookify.require-code-review-fixes.local.md`: `event: stop` で会話終了時にチェック
- このルール: `event: PostToolUse` でコードレビュー実行直後にチェック

このルールにより、コードレビュー実行直後に即座にブロック・リマインドされます。

## 動作

1. コードレビューでスコア 50 以上の指摘が見つかった場合:
   - 処理をブロック
   - 詳細な修正手順を表示
   - 最高スコアを表示

2. スコア 50 未満の指摘のみの場合:
   - 処理はブロックしない
   - リマインダーのみ表示

3. スコア情報がない場合:
   - `Found X issue(s)` から判定
   - リマインダーのみ表示
