---
name: pr-health-monitor
description: PR 作成直後に、PR 本文更新、コンフリクト確認、CI 監視、Codex レビュー、Copilot レビュー依頼と待機をまとめて進めるときに使う。明示的な `$pr-health-monitor` 呼び出し専用。
---

# PR ヘルスモニター

Claude Code の `/pr-health-monitor` 相当を Codex で扱うための skill です。

## 使い方

- `$pr-health-monitor <PR 番号または URL>`
- 例:
  - `$pr-health-monitor 456`
  - `$pr-health-monitor https://github.com/book000/dotfiles/pull/456`

## 目的

PR 作成後に必要な確認を漏れなく進める。

## 手順

1. PR 情報を解決する。
   - URL なら `OWNER / REPO / PR_NUMBER` を抽出する
   - 番号だけなら `gh-pr-target-repo.sh` の結果を優先して使う
   - つまり `upstream` remote があるリポジトリでは upstream PR を既定対象にする
2. コンフリクトを確認する。
   - `gh pr view "$PR_NUMBER" --json mergeable,mergeStateStatus,url`
   - コンフリクトがある場合は先に解消する
3. PR 本文を最新状態に更新する。
   - 概要
   - 変更内容
   - 検証内容
   - 前提・仮定・不確実性
4. CI を監視する。
   - `gh pr checks "$PR_NUMBER" --watch`
   - 失敗時は `gh run view <RUN_ID> --log-failed` で原因を確認して修正する
5. Codex のコードレビューを実行する。
   - `codex review --base origin/master`
   - 正しさ、回帰、セキュリティ、テスト漏れを優先して指摘を処理する
6. Copilot レビューを依頼する。
   - `request-review-copilot` が存在する場合のみ
   - `request-review-copilot "https://github.com/${OWNER}/${REPO}/pull/${PR_NUMBER}"`
7. Copilot レビュー待機を開始する。
   - `~/.agents/skills/pr-health-monitor/scripts/wait-for-copilot-review.sh "$PR_NUMBER_OR_URL" &`
   - 検出時は tmux 経由で `$handle-pr-reviews ...` を Codex セッションに送る
8. 各結果をまとめる。
   - CI
   - コンフリクト
   - PR 本文
   - Codex レビュー
   - Copilot レビュー待機状態

## 補足

- 並列化できる環境なら、CI 監視、PR 本文更新、Codex レビュー、Copilot 待機は並列で進める
- `codex review` が追加のリスクを指摘したら、PR 本文も同時に更新する
