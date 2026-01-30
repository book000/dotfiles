---
name: issue-pr
description: GitHub の issue を確認して対応し PR を作成
args:
  - name: issue_number
    description: GitHub の issue 番号
    required: true
    type: string
---

# Issue から PR を作成

以下の手順で GitHub の issue に対応して PR を作成してください：

## 前提条件の確認

1. 必要なコマンド（gh, jq）が利用可能であることを確認
2. Git リポジトリ内で実行されていることを確認
3. issue 番号が数値であることを確認

## Issue 情報の取得

issue 番号 `{{issue_number}}` の情報を以下のコマンドで取得してください：

```bash
gh issue view {{issue_number}} --json title,state,body
```

- issue が OPEN 状態でない場合は警告を表示
- issue のタイトルと本文を取得

## ブランチの作成

1. リモートリポジトリから最新の情報を取得：
   ```bash
   git fetch origin
   ```

2. デフォルトブランチを判定：
   - `git symbolic-ref refs/remotes/origin/HEAD` で取得
   - 取得できない場合は master または main を確認

3. issue タイトルからブランチ名を生成：
   - タイトルを小文字に変換
   - 英数字以外をハイフンに置換
   - 日本語のみのタイトルの場合は `issue-{{issue_number}}` を使用
   - ブランチタイプを決定：
     - タイトルが "fix" または "bug" で始まる場合: `fix/`
     - タイトルが "docs" または "doc" で始まる場合: `docs/`
     - タイトルが "refactor" で始まる場合: `refactor/`
     - それ以外: `feat/`

4. デフォルトブランチから新しいブランチを作成：
   ```bash
   git checkout -b <branch_name> origin/<default_branch>
   ```

## Issue への対応

issue の内容を確認し、適切な対応を行ってください。

## PR の作成

対応が完了したら、PR を作成してください：

```bash
gh pr create --title "<適切なタイトル>" --body "<PR 本文>"
```

PR 本文には以下を含めてください：
- Summary: 変更内容の概要
- 主な機能・変更点
- テスト結果

## 注意事項

- Conventional Commits に従ってコミットメッセージを作成
- コミット内容にセンシティブな情報が含まれていないことを確認
- Lint / Format エラーがないことを確認
- 動作確認を実施
