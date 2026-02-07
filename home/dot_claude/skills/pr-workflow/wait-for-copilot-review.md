---
name: wait-for-copilot-review
description: GitHub Copilot のレビューを検出し通知
trigger: Used after PR creation to wait for and detect GitHub Copilot review comments
---

# GitHub Copilot レビュー待機

PR 作成後、GitHub Copilot からのレビューコメントを自動的に検出して通知します。

## 使用方法

```bash
/wait-for-copilot-review <PR_NUMBER>
```

または、直接スクリプトを実行：

```bash
~/.claude/skills/pr-workflow/scripts/wait-for-copilot-review.sh <PR_NUMBER> &
```

## 機能

### 検出ロジック

- **プライマリ判定**: GraphQL API の `author.__typename` が `Bot` かどうか
- **セカンダリ判定**: `author.login` に `copilot` が含まれるか（補助的）
- **チェック間隔**: 30 秒
- **最大待機時間**: 30 分（60 回チェック）

### 検出条件

以下の条件を**すべて**満たすレビューを Copilot レビューとして検出：

1. `author.__typename` が `"Bot"` である
2. `author.login` に `"copilot"` が含まれる（部分一致）
3. `state` が `"COMMENTED"` または `"APPROVED"` である
4. `submittedAt` が null でない（完了したレビューのみ）

### バックグラウンド実行

- **ログファイル**: `~/.claude/logs/wait-copilot-review-<PR_NUMBER>.log`
- **ロックファイル**: `~/.claude/locks/wait-copilot-review-<PR_NUMBER>.lock`
- **排他制御**: flock による複数起動の防止

### 検出後の処理

1. ユーザーに通知（Discord 通知スクリプト利用）
2. レビューコメント数を表示
3. ログに検出結果を記録

## GraphQL クエリ

使用する GraphQL クエリ：

```graphql
query($owner: String!, $repo: String!, $number: Int!) {
  repository(owner: $owner, name: $repo) {
    pullRequest(number: $number) {
      reviews(first: 100) {
        nodes {
          author {
            login
            __typename
          }
          state
          submittedAt
        }
      }
    }
  }
}
```

## 注意事項

- 待機は最大 30 分です
- タイムアウトした場合でも、レビューは後で投稿される可能性があります
- 複数起動は flock により自動的に防止されます
- 実行状況はログファイルで確認できます

## トラブルシューティング

### ログの確認

```bash
tail -f ~/.claude/logs/wait-copilot-review-<PR_NUMBER>.log
```

### ロックファイルの削除（緊急時のみ）

```bash
rm ~/.claude/locks/wait-copilot-review-<PR_NUMBER>.lock
```

### 手動でのレビュー確認

```bash
gh api graphql -f owner="$OWNER" -f repo="$REPO" -F number=<PR_NUMBER> -f query='
query($owner: String!, $repo: String!, $number: Int!) {
  repository(owner: $owner, name: $repo) {
    pullRequest(number: $number) {
      reviews(first: 100) {
        nodes {
          author {
            login
            __typename
          }
          state
          submittedAt
        }
      }
    }
  }
}' --jq '.data.repository.pullRequest.reviews.nodes[] | select(.author.__typename == "Bot" and (.author.login | contains("copilot")))'
```
