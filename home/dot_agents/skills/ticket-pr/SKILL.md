---
name: ticket-pr
description: Jira チケットの調査、実装、ブランチ作成、PR 作成、PR 後フロー開始までを Codex で一貫して進めるときに使う。明示的な `$ticket-pr` 呼び出し専用。
---

# Jira チケットから PR を作成

Claude Code の `/ticket-pr` 相当を Codex で扱うための skill です。

## 使い方

- Codex CLI で `$ticket-pr` を選択し、Jira チケットキーまたは URL を渡す
- 例:
  - `$ticket-pr PROJECT-123`
  - `$ticket-pr https://company.atlassian.net/browse/PROJECT-123`

URL が渡された場合は、パスの末尾からチケットキーを抽出する。

## 前提

- Jira MCP (`mcp__atlassian__*`) が利用可能であること
- `gh` がインストール済みで認証済みであること
- 現在のリポジトリで作業すること
- 判断記録は Markdown ファイルではなく Jira チケットのコメントに残すこと

## ブランチタイプの決定

Jira の課題タイプからブランチタイプを決定する:

| Jira 課題タイプ | ブランチタイプ |
|---|---|
| Epic / Story / Task / New Feature / Improvement | `feat` |
| Bug | `fix` |
| Documentation | `docs` |
| Refactoring / Technical Debt | `refactor` |
| Sub-task | 親チケットに準拠、不明なら `feat` |

## ワークフロー

0. cloudId を解決する。
   - 引数が URL（例: `https://company.atlassian.net/browse/PROJECT-123`）の場合: ホスト名（例: `company.atlassian.net`）を `cloudId` として使用する
   - チケットキーのみの場合: `mcp__atlassian__getAccessibleAtlassianResources` で `cloudId` を取得する
1. Jira チケット情報を取得する。
   - `mcp__atlassian__getJiraIssue({ cloudId: "<cloud-id>", issueIdOrKey: "<key>" })`
   - Done / Closed / Resolved 等のステータスの場合は警告を表示し、処理を中断する
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
   - **重要**: ブランチ名に Jira チケットキーを含めない（ブランチ名は GitHub PR ページに表示されるため）
   - 例: `feat/add-user-authentication`
5. 実装する。
   - dotfiles では `home/` 配下の chezmoi ソースを更新する
   - 関連ドキュメントも同期する
6. 検証する。
   - 最低限、変更内容に対応する syntax / unit / integration テストを実行する
   - dotfiles の場合は `tests/` と `chezmoi apply` 系確認を優先する
7. コミットと push を行う。
   - Conventional Commits を使い、説明はプロジェクトの CLAUDE.md に従い、指定がない場合は日本語にする
8. PR を作成する。
   - `gh-pr-target-repo.sh` で PR 作成先のリポジトリを解決する
   - `upstream` remote が存在する場合は、それを既定の PR 作成先にする
   - PR 本文はプロジェクトの CLAUDE.md に従い、指定がない場合は日本語で、最新状態のみを記載する
   - 更新履歴の羅列は含めない
   - **重要**: PR のタイトル・本文には Jira チケットキーや Jira への言及を含めない
9. Jira チケットに完了コメントを投稿する。
   - `mcp__atlassian__addCommentToJiraIssue({ cloudId: "<cloud-id>", issueIdOrKey: "<key>", commentBody: "<PR URL を含む完了メッセージ>" })` で投稿
10. PR 作成後は直ちに `$pr-health-monitor` を使う。
    - 例: `$pr-health-monitor 456`

## 注意事項

- Codex CLI の公式機能では、Claude Code のような任意の custom slash command を追加しない。コマンド相当は skill に置き換える。
- レビュー待ちや CI 待ちの間に別作業へ逸れない。PR 後フローを最後まで回す。
- Jira への言及は GitHub Issues や PR には含めない。Jira チケット側にのみ記録する。
