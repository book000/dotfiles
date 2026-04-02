---
name: issue-pr
description: GitHub Issue の調査、実装、ブランチ作成、PR 作成、PR 後フロー開始までを Codex で一貫して進めるときに使う。明示的な `$issue-pr` 呼び出し専用。
---

# Issue から PR を作成

Claude Code の `/issue-pr` 相当を Codex で扱うための skill です。

## 使い方

- Codex CLI で `$issue-pr` を選択し、Issue 番号または URL を渡す
- 例:
  - `$issue-pr 123`
  - `$issue-pr https://github.com/book000/dotfiles/issues/123`

## 前提

- `gh` がインストール済みで認証済みであること
- 現在のリポジトリで作業すること
- 判断記録は Markdown ファイルではなく Issue コメントまたは PR 本文に残すこと

## ワークフロー

1. Issue 情報を取得する。
   - `gh issue view <issue> --json number,title,body,state,labels,comments,author,url`
   - すでに closed の Issue には着手しない
2. 要件と不確実性を整理する。
   - 変更対象
   - 想定されるリスク
   - 不明点
   - 外部仕様が絡む場合は必ず Web 検索や一次情報で確認する
3. 実装前の判断を行う。
   - 曖昧さが高く、実装を進めると危険ならユーザーに質問する
   - そうでなければ合理的な前提を明示して進める
4. ブランチを作成する。
   - `git fetch --all --prune`
   - ベースは `origin/master` を優先し、存在しなければデフォルトブランチを使う
   - ブランチ名は Conventional Branch に従う
5. 実装する。
   - dotfiles では `home/` 配下の chezmoi ソースを更新する
   - 関連ドキュメントも同期する
6. 検証する。
   - 最低限、変更内容に対応する syntax / unit / integration テストを実行する
   - dotfiles の場合は `tests/` と `chezmoi apply` 系確認を優先する
7. コミットと push を行う。
   - Conventional Commits を使い、説明は日本語にする
8. PR を作成する。
   - `gh-pr-target-repo.sh` で PR 作成先のリポジトリを解決する
   - `upstream` remote が存在する場合は、それを既定の PR 作成先にする
   - PR 本文は日本語で、最新状態のみを記載する
   - 更新履歴の羅列は含めない
9. PR 作成後は直ちに `$pr-health-monitor` を使う。
   - 例: `$pr-health-monitor 456`

## 注意事項

- Codex CLI の公式機能では、Claude Code のような任意の custom slash command を追加しない。コマンド相当は skill に置き換える。
- レビュー待ちや CI 待ちの間に別作業へ逸れない。PR 後フローを最後まで回す。
