---
name: ticket-pr
description: Investigate a Jira ticket, implement a fix, and create a PR end-to-end. For explicit /ticket-pr invocations only.
argument-hint: "[Jira ticket key or URL, e.g. PROJECT-123]"
disable-model-invocation: true
---

# Create PR from Jira Ticket

This skill operates in two modes: **plan mode** and **execution mode**.

`$ARGUMENTS` は Jira チケットのキー（例: `PROJECT-123`）または URL（例: `https://company.atlassian.net/browse/PROJECT-123`）を受け取る。
URL が渡された場合は、パスの末尾からチケットキーを抽出する。

## Mode Detection

Detected by checking if the system-reminder contains "Plan mode is active" or "plan file" (case-insensitive partial match).
If present: plan mode. Otherwise: execution mode (fallback).

---

## Plan Mode Workflow

### Phase 0: cloudId の解決

すべての Jira MCP ツール呼び出しに `cloudId` が必要。以下の手順で解決する:

1. `$ARGUMENTS` が URL（例: `https://company.atlassian.net/browse/PROJECT-123`）の場合:
   - ホスト名（例: `company.atlassian.net`）を `cloudId` として使用する
2. チケットキーのみの場合（例: `PROJECT-123`）:
   - `mcp__atlassian__getAccessibleAtlassianResources` で利用可能なサイトを取得し、対象の `cloudId` を特定する

### Phase 1: Jira チケット情報の取得

MCP ツール `mcp__atlassian__getJiraIssue` でチケット情報を取得する。

```
mcp__atlassian__getJiraIssue({
  cloudId: "<cloud-id>",
  issueIdOrKey: "<ticket-key>",
  fields: ["summary", "description", "issuetype", "status", "priority", "assignee", "comment"]
})
```

チケットが Done / Closed / Resolved / 完了 などのステータスの場合は警告を表示し、処理を中断する。

### Phase 2: 分析

1. チケットタイプの判定（feat / fix / docs / refactor）
   - Epic / Story / Task / New Feature / Improvement → `feat`
   - Bug → `fix`
   - Documentation → `docs`
   - Refactoring / Technical Debt → `refactor`
   - Sub-task → 親チケットのタイプに準拠、不明なら `feat`
2. 変更対象ファイルと影響範囲
3. 不明点のリスト

### Phase 3: ユーザーへの確認

不明点がある場合のみ AskUserQuestion ツールで確認する。
「このプランは問題ありませんか？」とは聞かない — それは ExitPlanMode の役割。

AskUserQuestion の制限事項: セッションあたり約 4〜6 回、各質問は 60 秒でタイムアウト、Task ツール経由のサブエージェントからは使用不可。

### Phase 4: 外部仕様の確認

外部依存や最新仕様が必要な場合は WebSearch や公式ドキュメント（Context7 など）で確認する。
（他のエージェントには相談しない。）

### Phase 5: 要件定義書の作成

以下のフォーマットで作成する:

```markdown
# <チケットキー> 要件定義

## 概要
- **チケットタイトル**: [タイトル]
- **チケットキー**: [PROJECT-123]
- **チケットタイプ**: Epic / Story / Task / Bug / ...
- **ブランチタイプ**: feat / fix / docs / refactor
- **影響範囲**: [ファイル・モジュール]

## 要件
### 機能要件
[詳細な機能要件]

### 非機能要件
- **セキュリティ**: [要件]
- **パフォーマンス**: [要件]

## 実装計画
### 主要ステップ
1. [ステップ 1]
2. [ステップ 2]

## ブランチ名
`<type>/<description>`

## 判断記録
1. 判断内容の要約
2. 検討した代替案
3. 採用しなかった案とその理由
4. 前提条件・仮定・不確実性
5. 他エージェントによるレビュー可否
```

### Phase 6: Jira チケットへのコメント投稿

MCP ツール `mcp__atlassian__addCommentToJiraIssue` で要件定義書をコメントとして投稿する。

```
mcp__atlassian__addCommentToJiraIssue({
  cloudId: "<cloud-id>",
  issueIdOrKey: "<ticket-key>",
  commentBody: "<要件定義書の内容>"
})
```

センシティブな情報が含まれていないことを必ず確認する。

### Phase 7: プランファイルへの書き込み

system-reminder で指定されたプランファイルパスに Write ツールで書き込む。

### Phase 8: ExitPlanMode の実行

```
ExitPlanMode()
```

---

## Execution Mode Workflow

### Prerequisites

- `gh` がインストール済みであること
- Git リポジトリ内で実行すること

### cloudId の解決

すべての Jira MCP ツール呼び出しに `cloudId` が必要。以下の手順で解決する:

1. `$ARGUMENTS` が URL（例: `https://company.atlassian.net/browse/PROJECT-123`）の場合:
   - ホスト名（例: `company.atlassian.net`）を `cloudId` として使用する
2. チケットキーのみの場合（例: `PROJECT-123`）:
   - `mcp__atlassian__getAccessibleAtlassianResources` で利用可能なサイトを取得し、対象の `cloudId` を特定する

### Jira チケット情報の取得

MCP ツール `mcp__atlassian__getJiraIssue` でチケット情報を取得する。

```
mcp__atlassian__getJiraIssue({
  cloudId: "<cloud-id>",
  issueIdOrKey: "<ticket-key>",
  fields: ["summary", "description", "issuetype", "status", "priority", "assignee", "comment"]
})
```

チケットが Done / Closed / Resolved 等のステータスの場合は警告を表示し、処理を中断する。

### ブランチタイプの決定

Jira の課題タイプからブランチタイプを決定する:

| Jira 課題タイプ | ブランチタイプ |
|---|---|
| Epic / Story / Task / New Feature / Improvement | `feat` |
| Bug | `fix` |
| Documentation | `docs` |
| Refactoring / Technical Debt | `refactor` |
| Sub-task | 親チケットに準拠、不明なら `feat` |

### ブランチの作成

`origin/master` を優先し、存在しなければデフォルトブランチを使う:

```bash
git fetch --all --prune
git checkout -b <branch_name> origin/master
```

ブランチ名は Conventional Branch に従う（例: `feat/add-user-authentication`）。
**重要**: ブランチ名に Jira チケットキーを含めない。ブランチ名は GitHub PR ページに表示されるため、Jira への言及に相当する。

### 実装

チケットの内容を確認し、適切に実装する。
dotfiles では `home/` 配下の chezmoi ソースファイルを更新する。
関連ドキュメント（README.md, CLAUDE.md 等）も合わせて更新する。

### 検証

変更内容に対応するテストを実行する。
dotfiles では `chezmoi apply` による動作確認を優先する。

### コミット

```bash
git add <files>
git commit -m "<type>: <日本語説明>"
```

Conventional Commits に従い、`<description>` は日本語で記載する。

### PR の作成

`gh-pr-target-repo.sh` で PR 作成先のリポジトリを解決する。`upstream` remote が存在する場合はそれを既定の作成先とする。

```bash
REPO=$(gh-pr-target-repo.sh 2>/dev/null || echo "")
gh pr create ${REPO:+--repo "$REPO"} --title "<title>" --body "<PR body>"
```

**重要**: PR のタイトル・本文には Jira チケットキーや Jira への言及を含めない。
PR 本文: 日本語で、最新状態のみ記載、更新履歴は含めない。

PR 本文の構成例:
```markdown
## 概要

[変更の概要を日本語で記載]

## 変更内容

- [変更点 1]
- [変更点 2]

## 動作確認

- [確認項目 1]
- [確認項目 2]
```

### Jira チケットへの作業完了コメント

PR 作成後、MCP ツール `mcp__atlassian__addCommentToJiraIssue` で PR URL を含む完了コメントを投稿する。

```
mcp__atlassian__addCommentToJiraIssue({
  cloudId: "<cloud-id>",
  issueIdOrKey: "<ticket-key>",
  commentBody: "実装完了しました。PR を作成しました: <PR URL>"
})
```

### PR 作成後

完了したら直ちに `/pr-health-monitor <PR number>` を実行する。

## Notes

- レビュー待ちや CI 待ちの間に別作業へ逸れない
- Jira への言及は PR 本文・GitHub Issue には含めない（Jira チケット側にのみ記録する）
- 判断記録は Jira チケットのコメントに残す
