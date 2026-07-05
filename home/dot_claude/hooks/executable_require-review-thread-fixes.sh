#!/bin/bash

# Stop hook: セッション終了時に未解決レビュースレッドをチェックし、対応を促す。
# PR 番号の取得優先順:
#   1. ~/.claude/data/session-state.json（issue-pr / ticket-pr スキルが書き出す）
#   2. transcript の JSONL パース（フォールバック）
# JSONL パースによりプレーンテキスト grep より確実に PR URL を抽出する。

# スキップ機能（緊急時や誤検知時）
if [[ "${SKIP_REVIEW_CHECK:-}" == "1" ]]; then
    exit 0
fi

STATE_FILE="$HOME/.claude/data/session-state.json"

# stdin から JSON を読み込む
INPUT=$(cat)
TRANSCRIPT_PATH=$(printf '%s' "$INPUT" | jq -r '.transcript_path // ""' 2>/dev/null)
SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // ""' 2>/dev/null)

# --- PR URL 解決 ---

PR_URL=""
# セッション状態ファイルの有効期限（24時間）
STATE_TTL=86400

# 優先 1: ステートファイル（スキルが書き出した構造化データ）
# TTL 以内かつ session_id が一致（または一方が空なら後方互換で許容）の場合のみ信頼する
if [[ -f "$STATE_FILE" ]]; then
    STATE_SESSION=$(jq -r '.session_id // ""' "$STATE_FILE" 2>/dev/null)
    STATE_TIMESTAMP=$(jq -r '.timestamp // 0' "$STATE_FILE" 2>/dev/null)
    CURRENT_TIME=$(date +%s)
    STATE_AGE=$(( CURRENT_TIME - STATE_TIMESTAMP ))
    if [[ "$STATE_AGE" -le "$STATE_TTL" ]]; then
        # 双方が空（session_id 導入前の完全な後方互換ケース）、または値が一致する
        # 場合のみ信頼する。SESSION_ID はあるのに STATE_SESSION が空（旧形式ファイル）
        # の場合は他セッション由来の可能性があるため採用せず、transcript パースへ
        # フォールバックする
        if [[ ( -z "$SESSION_ID" && -z "$STATE_SESSION" ) || "$SESSION_ID" == "$STATE_SESSION" ]]; then
            PR_URL=$(jq -r '.pr_url // ""' "$STATE_FILE" 2>/dev/null)
        fi
    fi
fi

# 優先 2: transcript の JSONL パース（プレーンテキスト grep より確実）
if [[ -z "$PR_URL" && -n "$TRANSCRIPT_PATH" && -f "$TRANSCRIPT_PATH" ]]; then
    PR_URL=$(jq -r '
        select(type == "object") |
        select(.type == "assistant") |
        .message.content[]? |
        if type == "string" then . else "" end |
        scan("https://github\\.com/[^/\\s]+/[^/\\s]+/pull/[0-9]+")
    ' "$TRANSCRIPT_PATH" 2>/dev/null | tail -1)
fi

# PR URL が取得できない場合はブロックしない（誤検知回避）
if [[ -z "$PR_URL" ]]; then
    exit 0
fi

# PR 番号を抽出する（Bash 正規表現で PCRE 非依存）
if [[ "$PR_URL" =~ /pull/([0-9]+) ]]; then
    PR_NUMBER="${BASH_REMATCH[1]}"
else
    exit 0
fi

# --- 「対応不要」メモリ機構のチェック ---
# ユーザーが明示的に mark-review-declined.sh を実行済みの PR は再警告しない
DECLINE_FILE="$HOME/.claude/data/review-declined-${SESSION_ID}.json"
if [[ -n "$SESSION_ID" && -f "$DECLINE_FILE" ]]; then
    IS_DECLINED=$(jq --argjson pr "$PR_NUMBER" '.declined_prs // [] | any(. == $pr)' "$DECLINE_FILE" 2>/dev/null)
    if [[ "$IS_DECLINED" == "true" ]]; then
        exit 0
    fi
fi

# --- owner/repo 解決 ---

REMOTE_URL=$(git remote get-url origin 2>/dev/null)
if [[ -z "$REMOTE_URL" ]]; then
    exit 0
fi

if [[ "$REMOTE_URL" =~ github\.com[:/]([^/]+)/([^/\.]+) ]]; then
    OWNER="${BASH_REMATCH[1]}"
    REPO="${BASH_REMATCH[2]}"
else
    exit 0
fi

# --- GraphQL で未解決レビュースレッドを取得 ---

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
              author { login }
              body
            }
          }
        }
      }
    }
  }
}' 2>/dev/null)

if [[ -z "$GRAPHQL_RESPONSE" ]]; then
    exit 0
fi

# 未解決スレッド数を確認する
UNRESOLVED_COUNT=$(printf '%s' "$GRAPHQL_RESPONSE" | \
    jq '[.data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved == false)] | length' 2>/dev/null)

if [[ -z "$UNRESOLVED_COUNT" || "$UNRESOLVED_COUNT" -eq 0 ]]; then
    exit 0
fi

# 未解決スレッド一覧を生成する（最初の 5 件まで）
THREAD_LIST=$(printf '%s' "$GRAPHQL_RESPONSE" | jq -r '
    [.data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved == false)] |
    to_entries[:5] |
    .[] |
    "[スレッド \(.key + 1)] @\(.value.comments.nodes[0].author.login // "unknown") - \(.value.path // "unknown"):\(.value.line // "N/A")\n  \"\(.value.comments.nodes[0].body // "" | .[0:100])\(if (.value.comments.nodes[0].body // "" | length) > 100 then "..." else "" end)\""
' 2>/dev/null | tr '\n' '\n')

if [[ "$UNRESOLVED_COUNT" -gt 5 ]]; then
    THREAD_LIST="${THREAD_LIST}
[...他 $((UNRESOLVED_COUNT - 5)) 件のスレッド]"
fi

# ブロックメッセージを生成する
MESSAGE="⚠️ **PR に ${UNRESOLVED_COUNT} 件の未解決レビュースレッドが残っています**

CLAUDE.md のルールに従い、**すべての未解決レビュースレッド**に対して必ず対応してから終了してください。

## 未解決スレッド一覧

${THREAD_LIST}

## 対応手順（順序通りに実施してください）

### 1. 各スレッドを確認・修正

\`\`\`bash
gh pr view ${PR_NUMBER} --web
\`\`\`

### 2. スレッドへ返信（issue コメントではなく thread reply を使用）

\`\`\`bash
gh api graphql -f query='mutation { addPullRequestReviewThreadReply(input: { pullRequestReviewThreadId: \"<THREAD_ID>\" body: \"対応内容\" }) { comment { id } } }'
\`\`\`

### 3. スレッドを resolve

\`\`\`bash
gh api graphql -f query='mutation { resolveReviewThread(input: { threadId: \"<THREAD_ID>\" }) { thread { id isResolved } } }'
\`\`\`

### 4. 全スレッド解決後にセッション終了を再試行

## よくある間違い

- ❌ issue コメントとして投稿 → \`addPullRequestReviewThreadReply\` を使用してください
- ❌ 返信後に resolve していない → 返信後は必ず \`resolveReviewThread\` を実行してください

## このセッション内でこの PR の警告を今後表示しない場合

\`\`\`bash
bash ~/.claude/hooks/mark-review-declined.sh ${PR_NUMBER}
\`\`\`

（このセッションが終了するまで、この PR に限定して再警告を抑止します。全チェックを毎回スキップする \`SKIP_REVIEW_CHECK=1\` とは異なります）

## 緊急スキップ

\`\`\`bash
SKIP_REVIEW_CHECK=1
\`\`\`"

jq -n --arg msg "$MESSAGE" '{"decision":"block","reason":$msg}'
exit 0
