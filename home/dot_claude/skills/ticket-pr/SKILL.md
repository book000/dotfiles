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

Detected by checking if the system-reminder contains "Plan mode is active" or "plan file".
If present: plan mode. Otherwise: execution mode.

---

## Plan Mode Workflow

### Phase 1: Jira チケット情報の取得

MCP ツール `mcp__atlassian__getJiraIssue` でチケット情報を取得する。

```
mcp__atlassian__getJiraIssue({ issueIdOrKey: "<ticket-key>" })
```

取得する情報:
- タイトル（summary）
- 説明（description）
- 課題タイプ（issuetype）
- ステータス（status）
- 優先度（priority）
- 担当者（assignee）
- コメント（comments）

チケットが Done / Closed / Resolved / 完了 などのステータスの場合は警告を表示する。

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

不明点がある場合は AskUserQuestion ツールで確認する。
「このプランは問題ありませんか？」とは聞かない — それは ExitPlanMode の役割。

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
  issueIdOrKey: "<ticket-key>",
  comment: "<要件定義書の内容>"
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

- `gh` と `jq` がインストール済みであること
- Git リポジトリ内で実行すること

### Jira チケット情報の取得

MCP ツール `mcp__atlassian__getJiraIssue` でチケット情報を取得する。

```
mcp__atlassian__getJiraIssue({ issueIdOrKey: "<ticket-key>" })
```

チケットが Done / Closed / Resolved 等のステータスの場合は警告を表示する。

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

```bash
git fetch origin
# デフォルトブランチを確認
git checkout -b <branch_name> origin/<default_branch>
```

ブランチ名は Conventional Branch に従う（例: `feat/add-user-authentication`）。
**重要**: ブランチ名に Jira チケットキーを含めない。ブランチ名は GitHub PR ページに表示されるため、Jira への言及に相当する。

### 実装

チケットの内容を確認し、適切に実装する。
dotfiles では `home/` 配下の chezmoi ソースファイルを更新する。

### PR の作成

```bash
gh pr create --title "<title>" --body "<PR body>"
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
  issueIdOrKey: "<ticket-key>",
  comment: "実装完了しました。PR を作成しました: <PR URL>"
})
```

### PR 作成後

完了したら直ちに `/pr-health-monitor <PR number>` を実行する。

## Notes

- レビュー待ちや CI 待ちの間に別作業へ逸れない
- Jira への言及は PR 本文・GitHub Issue には含めない（Jira チケット側にのみ記録する）
- 判断記録は Jira チケットのコメントに残す
