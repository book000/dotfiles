---
name: issue-pr
description: GitHub の Issue を調査・実装し PR を作成するまでを一貫して進めるときに使う。明示的な /issue-pr 呼び出し専用。
argument-hint: "[Issue番号またはURL]"
disable-model-invocation: true
---

# Issue から PR を作成

このスキルは **プランモード** と **実行モード** の 2 つのモードで動作します。

## モード検出

system-reminder に "Plan mode is active" または "plan file" を含むかで検出。
含む場合はプランモード、含まない場合は実行モード。

---

## プランモードワークフロー

### Phase 1: Issue 内容の分析

```bash
gh issue view $ARGUMENTS --json title,state,body,comments,author
```

以下を分析:
1. Issue の種類（feat/fix/docs/refactor）
2. 変更対象ファイル・影響範囲
3. 不明点のリスト

### Phase 2: ユーザーへの質問

AskUserQuestion ツールで不明点を確認。
「このプランで良いですか？」は ExitPlanMode の役割なので質問しない。

### Phase 3: 外部仕様の確認

外部依存・最新仕様が必要な場合は WebSearch や公式ドキュメント（Context7 等）で確認する。
（他エージェントへの相談は行わない）

### Phase 4: 要件定義書の作成

以下フォーマットで作成:

```markdown
# Issue #<番号> 要件定義書

## 概要
- **Issue タイトル**: [タイトル]
- **Issue 番号**: #[番号]
- **Issue 種別**: feat/fix/docs/refactor
- **影響範囲**: [ファイル/モジュール]

## 要件詳細
### 機能要件
[詳細な機能要件]

### 非機能要件
- **セキュリティ**: [要件]
- **パフォーマンス**: [要件]

## 実装方針
### 主要な実装ステップ
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

### Phase 5: Issue へのコメント投稿

```bash
gh issue comment $ARGUMENTS --body "$(cat <<'EOF'
[要件定義書の内容]
EOF
)"
```

機密情報が含まれていないことを必ず確認すること。

### Phase 6: プランファイルへの記載

system-reminder に記載されたプランファイルパスへ Write ツールで記載。

### Phase 7: ExitPlanMode の実行

```
ExitPlanMode()
```

---

## 実行モードワークフロー

### 前提確認

- `gh`、`jq` が利用可能であること
- Git リポジトリ内で実行されていること

### Issue 情報の取得

```bash
gh issue view $ARGUMENTS --json title,state,body,comments,author
```

Issue が OPEN でない場合は警告を表示。

### ブランチの作成

```bash
git fetch origin
# デフォルトブランチを確認
git checkout -b <branch_name> origin/<default_branch>
```

ブランチ名は Conventional Branch に従う（feat/fix/docs/refactor）。

### Issue への対応

Issue の内容を確認し、適切な実装を行う。
dotfiles では `home/` 配下の chezmoi ソースを更新する。

### PR の作成

```bash
gh pr create --title "<タイトル>" --body "<PR 本文>"
```

PR 本文は日本語・最新状態のみ・更新履歴なし。

### PR 作成後の対応

完了後、直ちに `/pr-health-monitor <PR番号>` を使う。

## 注意事項

- レビュー待ちや CI 待ちの間に別作業へ逸れない
- 判断記録は Issue コメントまたは PR 本文に残す（Markdown ファイルには書かない）
