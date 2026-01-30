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

3. issue の内容に基づいてブランチ名を生成：
   - issue の内容を確認し、適切なブランチ名を決定
   - ブランチタイプは CLAUDE.md の Conventional Branch の定義に従う：
     - バグ修正の場合: `fix/`
     - ドキュメント更新の場合: `docs/`
     - リファクタリングの場合: `refactor/`
     - 新機能追加の場合: `feat/`
   - ブランチ名は英数字とハイフンで構成し、内容を簡潔に表現
   - 例: `feat/add-user-authentication`, `fix/resolve-login-error`

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

## PR 作成後の対応

PR を作成したら、以下の手順を **必ず** 実施してください：

### 1. issue 作成者にレビューを依頼

権限がある場合、issue 作成者にレビューを依頼します：

```bash
# issue 作成者を取得
ISSUE_AUTHOR=$(gh issue view {{issue_number}} --json author --jq '.author.login')

# レビューを依頼（権限エラーの場合はスキップ）
gh pr edit <PR_NUMBER> --add-reviewer "$ISSUE_AUTHOR" 2>/dev/null || echo "レビュー依頼をスキップしました"
```

### 2. CI の確認

GitHub Actions CI が設定されている場合、以下のコマンドで CI の完了を待ちます：

```bash
gh pr checks <PR_NUMBER> --watch
```

CI が設定されていない場合は、ローカルで同等のテストを実行してください。

### 3. GitHub Copilot へのコードレビュー依頼

`request-review-copilot` コマンドが利用可能な場合、GitHub Copilot にレビューを依頼します：

```bash
request-review-copilot https://github.com/<OWNER>/<REPO>/pull/<PR_NUMBER>
```

### 4. レビューコメントへの対応

10 分以内に GitHub Copilot や他のユーザーからレビューコメントが投稿される場合があります。以下の手順で対応してください：

#### 4.1. レビューコメントの待機

レビューを待機します（最大 10 分、30秒ごとにチェック）：

```bash
# レビューの待機（最大 10 分）
echo "レビューを待機しています（最大10分）..."

OWNER="<OWNER>"
REPO="<REPO>"
PR_NUMBER=<PR_NUMBER>
MAX_WAIT=600  # 10分
INTERVAL=30   # 30秒ごとにチェック
ELAPSED=0

# PR 作成時のレビュー数を取得
INITIAL_REVIEW_COUNT=$(gh api graphql -f query="
query {
  repository(owner: \"$OWNER\", name: \"$REPO\") {
    pullRequest(number: $PR_NUMBER) {
      reviews {
        totalCount
      }
    }
  }
}" --jq '.data.repository.pullRequest.reviews.totalCount')

while [ $ELAPSED -lt $MAX_WAIT ]; do
  # 現在のレビュー数を確認
  CURRENT_REVIEW_COUNT=$(gh api graphql -f query="
  query {
    repository(owner: \"$OWNER\", name: \"$REPO\") {
      pullRequest(number: $PR_NUMBER) {
        reviews {
          totalCount
        }
      }
    }
  }" --jq '.data.repository.pullRequest.reviews.totalCount')

  if [ "$CURRENT_REVIEW_COUNT" -gt "$INITIAL_REVIEW_COUNT" ]; then
    echo "新しいレビューが投稿されました。"
    break
  fi

  sleep $INTERVAL
  ELAPSED=$((ELAPSED + INTERVAL))
  echo "待機中... ($ELAPSED / $MAX_WAIT 秒)"
done

if [ $ELAPSED -ge $MAX_WAIT ]; then
  echo "レビューが投稿されなかったため、スキップします。"
fi
```

#### 4.2. レビューコメントへの対応

レビューコメントが投稿された場合：

1. 各レビューコメントに対して適切に対応
2. 対応完了後、各レビュースレッドに返信
3. 対応したレビュースレッドのみ resolve

#### 4.3. レビュースレッドの resolve 方法

```bash
# レビュースレッド ID を取得
gh api graphql -f query='
query {
  repository(owner: "<OWNER>", name: "<REPO>") {
    pullRequest(number: <PR_NUMBER>) {
      reviewThreads(first: 10) {
        nodes {
          id
          isResolved
          comments(first: 1) {
            nodes {
              body
              path
            }
          }
        }
      }
    }
  }
}'

# スレッドを resolve
gh api graphql -f query='
mutation {
  resolveReviewThread(input: {threadId: "<THREAD_ID>"}) {
    thread {
      id
      isResolved
    }
  }
}'
```

### 5. コードレビューの実施

`/code-review:code-review` コマンドでコードレビューを実施し、スコア 50 以上の指摘事項に対応してください。

### 6. PR 本文の確認

PR 本文が最新の状態を正しく反映していることを確認し、必要に応じて更新してください。

## コミット前の注意事項

- Conventional Commits に従ってコミットメッセージを作成
- コミット内容にセンシティブな情報が含まれていないことを確認
- Lint / Format エラーがないことを確認
- 動作確認を実施
