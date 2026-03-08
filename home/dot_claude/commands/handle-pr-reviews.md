---
name: handle-pr-reviews
description: PR のレビュースレッドを一括処理する。全未解決スレッドを取得し、コード修正・返信・resolve・CI 確認を体系的に実施する。Copilot レビュー検出時にバックグラウンドスクリプトから自動実行される。
args:
  - name: pr_url_or_number
    description: GitHub PR の URL（https://github.com/OWNER/REPO/pull/NUMBER）または PR 番号
    required: true
    type: string
---

# PR レビュー一括処理

PR の全レビュースレッドを体系的に処理します。

---

## ステップ 0: PR 情報の解決

引数から OWNER・REPO・PR 番号を解決する。

```bash
# URL 形式の場合
PR_ARG="<引数>"
if echo "$PR_ARG" | grep -q 'github\.com'; then
  OWNER=$(echo "$PR_ARG" | grep -oP 'github\.com/\K[^/]+')
  REPO=$(echo "$PR_ARG" | grep -oP 'github\.com/[^/]+/\K[^/]+(?=/pull)')
  PR_NUMBER=$(echo "$PR_ARG" | grep -oP '/pull/\K\d+')
else
  # 番号のみの場合: 現在のリポジトリから取得
  OWNER=$(gh repo view --json owner --jq '.owner.login')
  REPO=$(gh repo view --json name --jq '.name')
  PR_NUMBER="$PR_ARG"
fi

echo "対象: https://github.com/${OWNER}/${REPO}/pull/${PR_NUMBER}"
```

---

## ステップ 1: ローカルリポジトリの特定と移動

コード修正が必要な場合に備え、ローカルクローンのパスを特定する。

```bash
LOCAL_REPO_PATH=""

# 1. 現在のディレクトリが対象リポジトリか確認
CURRENT_REMOTE=$(git remote get-url origin 2>/dev/null || true)
if echo "$CURRENT_REMOTE" | grep -q "${OWNER}/${REPO}"; then
  LOCAL_REPO_PATH=$(git rev-parse --show-toplevel 2>/dev/null)
fi

# 2. git で管理されている既知ディレクトリを remote URL で検索
#    検索対象ディレクトリは find コマンドで取得できる git リポジトリのトップレベルを使う
#    検索元は $HOME 配下および CLAUDE.md に記載された既知パスを使う
if [[ -z "$LOCAL_REPO_PATH" ]]; then
  while IFS= read -r -d '' gitdir; do
    dir=$(dirname "$gitdir")
    remote=$(git -C "$dir" remote get-url origin 2>/dev/null || true)
    if echo "$remote" | grep -q "${OWNER}/${REPO}"; then
      LOCAL_REPO_PATH="$dir"
      break
    fi
  done < <(find "$HOME" -maxdepth 8 \( -name ".git" -type f -o -name ".git" -type d \) -print0 2>/dev/null)
fi

echo "ローカルパス: ${LOCAL_REPO_PATH:-（見つからない、gh API のみで対応）}"
```

---

## ステップ 2: 全未解決レビュースレッドの取得

**注意: このステップで取得した全スレッドを処理する。取得漏れを防ぐため、必ず GraphQL で取得すること。**

```bash
GRAPHQL_RESPONSE=$(gh api graphql \
  -f owner="$OWNER" \
  -f repo="$REPO" \
  -F number="$PR_NUMBER" \
  -f query='
query($owner: String!, $repo: String!, $number: Int!) {
  repository(owner: $owner, name: $repo) {
    pullRequest(number: $number) {
      reviewThreads(first: 100) {
        # 注意: 最大 100 件まで取得。100 件を超える場合は pageInfo.hasNextPage と
        # pageInfo.endCursor を使ったカーソルページネーションが必要
        nodes {
          id
          isResolved
          path
          line
          startLine
          diffSide
          comments(first: 10) {
            nodes {
              id
              author {
                login
                __typename
              }
              body
              createdAt
            }
          }
        }
      }
    }
  }
}')

# 未解決スレッドのみ抽出
UNRESOLVED=$(echo "$GRAPHQL_RESPONSE" | jq '[.data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved == false)]')
COUNT=$(echo "$UNRESOLVED" | jq 'length')
echo "未解決スレッド数: $COUNT"
```

スレッドが 0 件の場合は「未解決スレッドなし」を報告して終了。

---

## ステップ 3: 各スレッドへの対応

**全スレッドを 1 件ずつ、以下の手順で処理すること。スキップ禁止。**

各スレッドについて:

### 3a. コメント内容の確認

```bash
THREAD_ID=$(echo "$thread" | jq -r '.id')
THREAD_PATH=$(echo "$thread" | jq -r '.path // ""')
THREAD_LINE=$(echo "$thread" | jq -r '.line // 0')
# 最新コメント（最後の要素）を参照する。nodes[0] は最初のコメントであり、
# 後から追加された返信を見落とす可能性があるため last を使う
AUTHOR=$(echo "$thread" | jq -r '.comments.nodes | last | .author.login')
COMMENT=$(echo "$thread" | jq -r '.comments.nodes | last | .body')
echo "スレッド: $THREAD_ID | $AUTHOR | $THREAD_PATH:$THREAD_LINE"
echo "コメント: $COMMENT"
```

### 3b. 対象コードの確認（パスがある場合）

`THREAD_PATH` が空でない場合、対象ファイルを Read ツールで読み込み、該当行周辺を確認する。

### 3c. 対応判断と実施

| 判断 | 対応 |
|------|------|
| コード修正が必要 | 修正を実施（Edit ツール使用）。`CHANGES_MADE=true` を記録 |
| 修正不要・現状維持 | その理由を明確にまとめる |
| 質問への回答 | 回答内容をまとめる |

### 3d. スレッドへの返信投稿

**必ず `addPullRequestReviewThreadReply` mutation を使うこと。issue コメントとして投稿してはいけない。**

```bash
REPLY_BODY="対応内容を記載"
# -f を使うことで特殊文字・改行を含む本文も安全に渡せる
gh api graphql \
  -f threadId="${THREAD_ID}" \
  -f body="${REPLY_BODY}" \
  -f query='
mutation($threadId: ID!, $body: String!) {
  addPullRequestReviewThreadReply(input: {
    pullRequestReviewThreadId: $threadId
    body: $body
  }) {
    comment { id }
  }
}'
```

返信内容の例:
- コード修正した場合: 「ご指摘ありがとうございます。〇〇の問題を修正しました。△△の理由により〜〜に変更しました。」
- 現状維持の場合: 「ご指摘の点を確認しました。〇〇の理由により現状維持とします。」

### 3e. スレッドの resolve

**返信後、必ず resolve すること。**

```bash
gh api graphql -f query="
mutation {
  resolveReviewThread(input: {threadId: \"${THREAD_ID}\"}) {
    thread { id isResolved }
  }
}"
```

---

## ステップ 4: コード変更のコミット・プッシュ

`CHANGES_MADE=true` の場合のみ実施:

```bash
# 変更ファイルを確認
git -C "$LOCAL_REPO_PATH" status

# Conventional Commits に従いコミット（説明は日本語）
# add -p は対話的なため使わず、編集したファイルを明示的にステージする
git -C "$LOCAL_REPO_PATH" add <編集したファイルのパスを列挙>
git -C "$LOCAL_REPO_PATH" commit -m "fix: レビューコメントに基づく修正"

# SSH でプッシュ
git -C "$LOCAL_REPO_PATH" push
```

---

## ステップ 5: 全未解決スレッドの再確認

**対応漏れがないことを確認するため、必ず GraphQL で再取得する。**

```bash
RECHECK=$(gh api graphql \
  -f owner="$OWNER" -f repo="$REPO" -F number="$PR_NUMBER" \
  -f query='
query($owner: String!, $repo: String!, $number: Int!) {
  repository(owner: $owner, name: $repo) {
    pullRequest(number: $number) {
      reviewThreads(first: 100) {
        # 注意: 最大 100 件まで取得。ステップ 2 と同様に 100 件超の場合はページネーションが必要
        nodes { id isResolved }
      }
    }
  }
}' | jq '[.data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved == false)] | length')

if [[ "$RECHECK" -gt 0 ]]; then
  echo "⚠️ 未解決スレッドが $RECHECK 件残っています。ステップ 3 に戻って対応する。"
else
  echo "✅ 全スレッド resolve 完了"
fi
```

---

## ステップ 6: CI 最終確認

```bash
gh pr checks "$PR_NUMBER" --watch
```

CI が失敗した場合: ログを確認して修正し、再プッシュ・再確認する。

---

## ステップ 7: 完了報告

以下のフォーマットで報告する:

```
✅ PR #<番号> レビュー処理完了
   対応スレッド: N 件
   コード修正: あり / なし
   CI: 全チェック通過
   残り未解決スレッド: 0 件
```

---

## 注意事項

- **`addPullRequestReviewThreadReply`** を使うこと（issue コメントは不可）
- 返信してから必ず resolve すること（返信だけで resolve しないのは違反）
- Copilot・book000 含む全レビュアーのコメントを処理すること
- resolve 後に新しいコメントが追加されていないか最後に確認すること
