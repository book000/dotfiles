---
name: handle-pr-reviews
description: GitHub PR の未解決レビュースレッドを GraphQL で取得し、修正、返信、resolve、再確認まで体系的に進めるときに使う。明示的な `$handle-pr-reviews` 呼び出し専用。
---

# PR レビュー一括処理

Claude Code の `/handle-pr-reviews` 相当を Codex で扱うための skill です。

## 使い方

- `$handle-pr-reviews <PR 番号または URL>`
- 例:
  - `$handle-pr-reviews 456`
  - `$handle-pr-reviews https://github.com/book000/dotfiles/pull/456`

## 手順

1. PR 情報を解決する。
   - 番号のみなら `gh-pr-target-repo.sh` の結果を優先して使う
   - つまり `upstream` remote があるリポジトリでは upstream PR を既定対象にする
2. 全未解決レビュースレッドを GraphQL で取得する。
   - `reviewThreads(first: 100)` を使用する
   - 100 件を超える可能性がある場合はページネーションも考慮する
3. 各スレッドを 1 件ずつ処理する。
   - 最新コメントを確認する
   - 修正が必要ならコードを直す
   - 修正不要なら理由を整理する
4. スレッドへ返信する。
   - `addPullRequestReviewThreadReply` mutation を使う
   - issue コメントとして返信してはいけない
5. 対応済みスレッドを resolve する。
   - `resolveReviewThread` mutation を使う
6. 変更があればコミットと push を行う。
   - Conventional Commits を使う
7. 未解決スレッドを再取得して 0 件を確認する。
8. `gh pr checks "$PR_NUMBER" --watch` で CI を再確認する。

## 注意事項

- 返信してから resolve する順序を守る
- 1 件だけ見て終わらず、全スレッドを再取得して漏れを確認する
- レビュー対応後は PR 本文も最新状態に合わせて更新する
