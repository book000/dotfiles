---
name: code-review-immediate-fix
enabled: true
event: PostToolUse
tool: Skill
condition: |
  toolInput.skill === "code-review:code-review"
action: |
  const commentMatch = toolResult.match(/Found (\d+) issue/);
  if (commentMatch) {
    const issueCount = parseInt(commentMatch[1]);
    if (issueCount > 0) {
      return {
        block: true,
        message: `⚠️ コードレビューで ${issueCount} 件の指摘事項が見つかりました。\n\nCLAUDE.md の規則により、スコア 50 以上の指摘事項に対して必ず対応してください。\n\n次のステップ:\n1. 指摘された問題をすべて修正する\n2. 修正内容をコミット・プッシュする\n3. PR 本文を更新する\n4. 必要に応じて再度コードレビューを実施する\n\n指摘事項への対応を完了してから次に進んでください。`
      };
    }
  }
---

# コードレビュー直後の修正を促す

このルールは、`/code-review:code-review` スキル実行直後に指摘事項が見つかった場合、即座に修正を促すためのものです。

## 既存ルールとの違い

- `hookify.require-code-review-fixes.local.md`: `event: stop` で会話終了時にチェック
- このルール: `event: PostToolUse` でコードレビュー実行直後にチェック

両方のルールにより、二重の安全網を提供します。

## 動作

コードレビューで issue が見つかった場合、即座に処理をブロックし、修正を促すメッセージを表示します。
