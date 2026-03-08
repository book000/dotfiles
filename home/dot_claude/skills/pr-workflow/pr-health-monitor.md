---
name: pr-health-monitor
description: PR作成後の監視・対応フローを自動化する。CI確認・Copilotレビュー待機・コードレビュー・コンフリクト確認・PR本文更新を並列実行する。
trigger: Use /pr-health-monitor <PR_NUMBER_OR_URL> immediately after creating a PR to automate the full post-PR checklist
---

# PR ヘルスモニター

PR 作成後のチェックリスト全体を自動化します。

## 使用方法

```
/pr-health-monitor <PR番号またはURL>
```

**例:**
- `/pr-health-monitor 123`
- `/pr-health-monitor https://github.com/owner/repo/pull/123`

---

## ステップ 0: PR 情報の解決

引数から OWNER・REPO・PR 番号を解決する。

```bash
# URL 形式の場合
echo "https://github.com/owner/repo/pull/123" | grep -oP 'github\.com/([^/]+)/([^/]+)/pull/(\d+)'
# → OWNER=owner, REPO=repo, PR_NUMBER=123

# 番号のみの場合（現在のリポジトリから取得）
OWNER=$(gh repo view --json owner --jq '.owner.login')
REPO=$(gh repo view --json name --jq '.name')
PR_NUMBER=<引数>
```

PR の URL を確認:

```bash
gh pr view "$PR_NUMBER" --json url --jq '.url'
```

---

## ステップ 1: 並列実行フェーズ

**Task ツールを使い、以下をすべて並列で実行すること。**

### Task A: Copilot レビュー依頼 → バックグラウンド待機

```bash
# Copilot にレビューを依頼
request-review-copilot "https://github.com/${OWNER}/${REPO}/pull/${PR_NUMBER}"

# バックグラウンドで Copilot レビューを待機
# 検出時は自動的に /handle-pr-reviews が tmux 経由で実行される
~/.claude/skills/pr-workflow/scripts/wait-for-copilot-review.sh "$PR_NUMBER" &
echo "Copilot レビュー待機を開始（バックグラウンド）"
echo "ログ: ~/.claude/logs/wait-copilot-review-${PR_NUMBER}.log"
```

### Task B: CI 確認

```bash
gh pr checks "$PR_NUMBER" --watch
```

CI が失敗している場合:
1. `gh run view <RUN_ID> --log-failed` でログを確認
2. 原因を特定して修正
3. コミット・プッシュ後、再度 CI が通るまで待機

### Task C: コンフリクト確認

```bash
gh pr view "$PR_NUMBER" --json mergeable,mergeStateStatus --jq '{mergeable,mergeStateStatus}'
```

コンフリクトがある場合はベースブランチをマージして解消する。

### Task D: PR 本文更新

CLAUDE.md のルールに従い、PR 本文を現在のブランチの最終状態のみ・漏れなく・日本語で記載する。
過去の更新履歴は含めない。

```bash
gh pr edit "$PR_NUMBER" --body "$(cat <<'BODY'
## 概要
...

## 変更内容
...

## 確認方法
...
BODY
)"
```

### Task E: コードレビュー

`/code-review:code-review` を実行してコードレビューを行う。

スコア 50 以上の指摘事項がある場合は **即座に修正**すること（CLAUDE.md ルール）。

---

## ステップ 2: 完了報告

各タスクの結果をまとめて報告する。以下のフォーマットで:

```
✅ CI: 全チェック通過
✅ コンフリクト: なし
✅ PR 本文: 更新済み
✅ コードレビュー: スコア X（指摘 N 件対応済み）
⏳ Copilot レビュー待機: バックグラウンドで継続中
   → 検出時は自動的に /handle-pr-reviews が実行されます
   → ログ: ~/.claude/logs/wait-copilot-review-<PR_NUMBER>.log
```

---

## フェーズ 2: Copilot レビュー検出後（自動実行）

バックグラウンドスクリプトが Copilot レビューを検出すると、tmux 経由で以下が自動実行される:

```
/handle-pr-reviews https://github.com/OWNER/REPO/pull/PR_NUMBER
```

これにより、全レビュースレッドへの返信・resolve・CI 最終確認が自動で行われる。

---

## 注意事項

- `request-review-copilot` コマンドが存在しない場合はスキップしてよい
- Copilot レビューが 30 分以内に来ない場合はタイムアウトし、tmux に通知が届く
- コードレビューと CI は長時間かかる場合があるため、Task ツールで並列実行すること
