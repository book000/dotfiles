#!/bin/bash

# PR レビュースレッド対応漏れ防止フック
# セッション終了時に未解決レビュースレッドをチェックし、対応を促す

# スキップ機能（緊急時や誤検知時）
if [[ "${SKIP_REVIEW_CHECK:-}" == "1" ]]; then
  echo '{"block":false}'
  exit 0
fi

# 環境変数から transcript パスを取得
TRANSCRIPT_PATH="${TRANSCRIPT_PATH:-}"

# transcript ファイルが存在しない場合
if [[ -z "$TRANSCRIPT_PATH" ]] || [[ ! -f "$TRANSCRIPT_PATH" ]]; then
  echo '{"block":false}'
  exit 0
fi

# PR 番号を抽出（複数パターンで試行）
PR_NUMBER=""

# パターン1: gh pr create の出力から URL を抽出
PR_URL=$(grep -oP 'https://github\.com/[^/]+/[^/]+/pull/\d+' "$TRANSCRIPT_PATH" 2>/dev/null | tail -1)
if [[ -n "$PR_URL" ]]; then
  PR_NUMBER=$(echo "$PR_URL" | grep -oP '/pull/\K\d+' 2>/dev/null)
fi

# パターン2: request-review-copilot の引数から URL を抽出
if [[ -z "$PR_NUMBER" ]]; then
  PR_URL=$(grep -oP 'request-review-copilot\s+https://github\.com/[^/]+/[^/]+/pull/\d+' "$TRANSCRIPT_PATH" 2>/dev/null | tail -1 | grep -oP 'https://[^\s]+')
  if [[ -n "$PR_URL" ]]; then
    PR_NUMBER=$(echo "$PR_URL" | grep -oP '/pull/\K\d+' 2>/dev/null)
  fi
fi

# パターン3: transcript 内の /pull/NUMBER から抽出
if [[ -z "$PR_NUMBER" ]]; then
  PR_NUMBER=$(grep -oP '/pull/\K\d+' "$TRANSCRIPT_PATH" 2>/dev/null | tail -1)
fi

# PR 番号が取得できない場合はブロックしない（誤検知回避）
if [[ -z "$PR_NUMBER" ]]; then
  echo '{"block":false}'
  exit 0
fi

# git remote から owner/repo を抽出
REMOTE_URL=$(git remote get-url origin 2>/dev/null)
if [[ -z "$REMOTE_URL" ]]; then
  echo '{"block":false}'
  exit 0
fi

# HTTPS URL の場合: https://github.com/owner/repo.git
# SSH URL の場合: git@github.com:owner/repo.git
if [[ "$REMOTE_URL" =~ github\.com[:/]([^/]+)/([^/\.]+) ]]; then
  OWNER="${BASH_REMATCH[1]}"
  REPO="${BASH_REMATCH[2]}"
else
  echo '{"block":false}'
  exit 0
fi

# GraphQL API で未解決レビュースレッドを取得
# セキュリティのため、変数をパラメータ化して使用
# shellcheck disable=SC2016
GRAPHQL_RESPONSE=$(gh api graphql \
  -f owner="$OWNER" \
  -f repo="$REPO" \
  -F number="$PR_NUMBER" \
  -f query='
query($owner: String!, $repo: String!, $number: Int!) {
  repository(owner: $owner, name: $repo) {
    pullRequest(number: $number) {
      reviewThreads(first: 100) {
        nodes {
          id
          isResolved
          path
          line
          comments(first: 1) {
            nodes {
              author {
                login
              }
              body
            }
          }
        }
      }
    }
  }
}
' 2>/dev/null)

# GraphQL API エラーの場合はブロックしない
if [[ -z "$GRAPHQL_RESPONSE" ]]; then
  echo '{"block":false}'
  exit 0
fi

# 未解決スレッドを抽出
UNRESOLVED_THREADS=$(echo "$GRAPHQL_RESPONSE" | jq -r '.data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved == false)' 2>/dev/null)

# 未解決スレッドがない場合はブロックしない
if [[ -z "$UNRESOLVED_THREADS" ]]; then
  echo '{"block":false}'
  exit 0
fi

# 未解決スレッド数をカウント
UNRESOLVED_COUNT=$(echo "$UNRESOLVED_THREADS" | jq -s 'length' 2>/dev/null)

# 未解決スレッド一覧を生成（最初の 5 件まで）
THREAD_LIST=""
THREAD_INDEX=1
while IFS= read -r thread; do
  if [[ $THREAD_INDEX -gt 5 ]]; then
    THREAD_LIST="${THREAD_LIST}\n[...他 $((UNRESOLVED_COUNT - 5)) 件のスレッド]"
    break
  fi

  # shellcheck disable=SC2034
  THREAD_ID=$(echo "$thread" | jq -r '.id' 2>/dev/null)
  THREAD_PATH=$(echo "$thread" | jq -r '.path // "unknown"' 2>/dev/null)
  THREAD_LINE=$(echo "$thread" | jq -r '.line // "N/A"' 2>/dev/null)
  AUTHOR_LOGIN=$(echo "$thread" | jq -r '.comments.nodes[0].author.login // "unknown"' 2>/dev/null)
  COMMENT_BODY=$(echo "$thread" | jq -r '.comments.nodes[0].body // ""' 2>/dev/null)

  # コメント冒頭 100 文字
  COMMENT_PREVIEW=$(echo "$COMMENT_BODY" | head -c 100)
  if [[ ${#COMMENT_BODY} -gt 100 ]]; then
    COMMENT_PREVIEW="${COMMENT_PREVIEW}..."
  fi

  THREAD_LIST="${THREAD_LIST}\n[スレッド $THREAD_INDEX] @$AUTHOR_LOGIN - $THREAD_PATH:$THREAD_LINE\n  \"$COMMENT_PREVIEW\""
  THREAD_INDEX=$((THREAD_INDEX + 1))
done < <(echo "$GRAPHQL_RESPONSE" | jq -c '.data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved == false)' 2>/dev/null)

# ブロックメッセージを生成
MESSAGE="⚠️ **PR に $UNRESOLVED_COUNT 件の未解決レビュースレッドが残っています**

CLAUDE.md のルールに従い、**すべての未解決レビュースレッド**に対して必ず対応してから終了してください。

## 未解決スレッド一覧
$THREAD_LIST

## 対応が必要な理由

- 未解決レビューコメントを放置すると、コードの品質や保守性に影響が出る可能性があります
- レビューコメントは重要なフィードバックであり、対応漏れは避けるべきです
- GitHub Copilot や他のレビュアーからのコメントはすべて対応が必要です

## 対応手順（重要：必ず順序通りに実施してください）

### 0. レビューコメントをブラウザで確認（推奨）

\`\`\`bash
gh pr view $PR_NUMBER --web
\`\`\`

または、CLI で未解決スレッドを確認:

\`\`\`bash
OWNER=\"$OWNER\"
REPO=\"$REPO\"
PR_NUMBER=$PR_NUMBER

gh api graphql -f query='
query {
  repository(owner: \"'\$OWNER'\", name: \"'\$REPO'\") {
    pullRequest(number: '\$PR_NUMBER') {
      reviewThreads(first: 100) {
        nodes {
          id
          isResolved
          path
          line
          comments(first: 10) {
            nodes {
              author { login }
              body
            }
          }
        }
      }
    }
  }
}' --jq '.data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved == false)'
\`\`\`

### 1. 各レビュースレッドに対して対応

**各スレッドごとに以下を実施:**

a. レビューコメントの内容を確認し、対応が必要か判断
b. 対応が必要な場合は適切な修正を実施
c. 修正内容をコミット・プッシュ（必要に応じて）

### 2. 各レビュースレッドに返信を投稿（重要）

**注意**: 通常のコメント（issue コメント）として投稿してはいけません。
**必ず** \`addPullRequestReviewThreadReply\` mutation を使用してスレッドに返信してください。

\`\`\`bash
# 各レビュースレッド ID に対して実行
THREAD_ID=\"取得したスレッド ID\"
gh api graphql -f query='
mutation {
  addPullRequestReviewThreadReply(input: {
    pullRequestReviewThreadId: \"'\$THREAD_ID'\"
    body: \"対応内容を記載（修正した内容、理由、または現状維持の判断など）\"
  }) {
    comment { id }
  }
}'
\`\`\`

### 3. 対応が完了したレビュースレッドを resolve

**注意**: 返信を投稿した後、**必ず** resolve してください。

\`\`\`bash
# 各レビュースレッド ID に対して実行
gh api graphql -f query='
mutation {
  resolveReviewThread(input: {threadId: \"'\$THREAD_ID'\"}) {
    thread {
      id
      isResolved
    }
  }
}'
\`\`\`

### 4. 再度すべての未解決レビュースレッドを確認

手順 0 のコマンドを再度実行し、すべてのスレッドが resolved になっていることを確認してください。

### 5. セッション終了を再試行

すべてのスレッドが resolved になったら、セッションを終了してください。フックが再度実行され、今度は通過するはずです。

## 緊急時のスキップ方法

どうしてもレビューコメントへの対応を後回しにしたい場合（誤検知など）:

\`\`\`bash
SKIP_REVIEW_CHECK=1 # フックをスキップ
\`\`\`

**注意**: この方法は緊急時のみ使用し、後で必ず対応してください。

## よくある間違い

❌ 通常のコメント（issue コメント）として投稿している → **\`addPullRequestReviewThreadReply\` を使用してください**
❌ 返信を投稿したが resolve していない → **返信後は必ず \`resolveReviewThread\` を実行してください**
❌ 一部のスレッドだけ対応している → **すべてのスレッドに対応してください**
❌ レビューがまだ来ていないのにセッションを終了しようとしている → **レビューが来るまで待つか、後で確認してください**"

jq -n --arg msg "$MESSAGE" '{"block":true,"message":$msg}'
exit 0
