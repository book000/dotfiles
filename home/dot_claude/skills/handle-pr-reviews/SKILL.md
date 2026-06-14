---
name: handle-pr-reviews
description: Process all PR review threads in bulk. Fetches all unresolved threads and systematically applies code fixes, replies, and resolves. Auto-triggered by background script on Copilot review detection.
argument-hint: "[PR URL or PR number]"
---

# PR Review Bulk Processing

Systematically process all review threads in a PR.

---

## Step 0: Resolve PR Info

Resolve OWNER, REPO, and PR number from the argument.

```bash
# When URL format
PR_ARG="$ARGUMENTS"
if echo "$PR_ARG" | grep -q 'github\.com'; then
  OWNER=$(echo "$PR_ARG" | grep -oP 'github\.com/\K[^/]+')
  REPO=$(echo "$PR_ARG" | grep -oP 'github\.com/[^/]+/\K[^/]+(?=/pull)')
  PR_NUMBER=$(echo "$PR_ARG" | grep -oP '/pull/\K\d+')
else
  # Number only: get from current repository
  OWNER=$(gh repo view --json owner --jq '.owner.login')
  REPO=$(gh repo view --json name --jq '.name')
  PR_NUMBER="$PR_ARG"
fi

echo "Target: https://github.com/${OWNER}/${REPO}/pull/${PR_NUMBER}"
```

---

## Step 1: Locate Local Repository

Locate the local clone path in case code fixes are needed.

```bash
LOCAL_REPO_PATH=""

# 1. Check if the current directory is the target repository
CURRENT_REMOTE=$(git remote get-url origin 2>/dev/null || true)
if echo "$CURRENT_REMOTE" | grep -q "${OWNER}/${REPO}"; then
  LOCAL_REPO_PATH=$(git rev-parse --show-toplevel 2>/dev/null)
fi

# 2. Search known directories by remote URL
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

echo "Local path: ${LOCAL_REPO_PATH:-(not found, using gh API only)}"
```

---

## Step 2: Fetch All Unresolved Review Threads

**Important: process every thread fetched here. Always use GraphQL to avoid missing any.**

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
        # Note: fetches up to 100 threads. For > 100, use cursor pagination
        # with pageInfo.hasNextPage and pageInfo.endCursor
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

# Extract only unresolved threads
UNRESOLVED=$(echo "$GRAPHQL_RESPONSE" | jq '[.data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved == false)]')
COUNT=$(echo "$UNRESOLVED" | jq 'length')
echo "Unresolved threads: $COUNT"
```

If count is 0, report "no unresolved threads" and exit.

---

## Step 3: Handle Each Thread

**Process every thread one by one in the following order. Skipping is not allowed.**

### 3a. Read Thread Content

```bash
THREAD_ID=$(echo "$thread" | jq -r '.id')
THREAD_PATH=$(echo "$thread" | jq -r '.path // ""')
THREAD_LINE=$(echo "$thread" | jq -r '.line // 0')
# Reference the last comment (most recent reply); nodes[0] is the first comment
# and may miss later replies
AUTHOR=$(echo "$thread" | jq -r '.comments.nodes | last | .author.login')
COMMENT=$(echo "$thread" | jq -r '.comments.nodes | last | .body')
echo "Thread: $THREAD_ID | $AUTHOR | $THREAD_PATH:$THREAD_LINE"
echo "Comment: $COMMENT"
```

### 3b. Read Target Code (if path present)

If `THREAD_PATH` is not empty, read the target file with the Read tool and check the relevant lines.

### 3c. Decide and Act

| Decision | Action |
|------|------|
| Code fix needed | Apply fix (use Edit tool). Record `CHANGES_MADE=true` |
| No fix needed | Clearly document the reason |
| Answer to a question | Summarize the answer |

### 3d. Post Reply to Thread

**Always use the `addPullRequestReviewThreadReply` mutation. Do not post as an issue comment.**

```bash
REPLY_BODY="describe the action taken"
# Using -f safely passes body text containing special characters and newlines
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

Reply examples:
- When code was fixed: "Thank you for the feedback. Fixed the issue with ○○. Changed to △△ because of ~~."
- When keeping as-is: "Reviewed the point raised. Keeping the current implementation because of ○○."

### 3e. Resolve the Thread

**Always resolve after replying.**

```bash
gh api graphql -f query="
mutation {
  resolveReviewThread(input: {threadId: \"${THREAD_ID}\"}) {
    thread { id isResolved }
  }
}"
```

---

## Step 4: Commit and Push Code Changes

Only when `CHANGES_MADE=true`:

```bash
# Check changed files
git -C "$LOCAL_REPO_PATH" status

# Commit following Conventional Commits
# description language: follow the project CLAUDE.md if specified; otherwise Japanese
# Explicitly stage edited files instead of using interactive add
git -C "$LOCAL_REPO_PATH" add <list edited file paths>
git -C "$LOCAL_REPO_PATH" commit -m "fix: <description in the project language>"

# Push via SSH
git -C "$LOCAL_REPO_PATH" push
```

---

## Step 5: Re-verify All Unresolved Threads

**Always re-fetch via GraphQL to confirm nothing was missed.**

```bash
RECHECK=$(gh api graphql \
  -f owner="$OWNER" -f repo="$REPO" -F number="$PR_NUMBER" \
  -f query='
query($owner: String!, $repo: String!, $number: Int!) {
  repository(owner: $owner, name: $repo) {
    pullRequest(number: $number) {
      reviewThreads(first: 100) {
        # Note: up to 100 threads. Paginate if > 100 (same as Step 2)
        nodes { id isResolved }
      }
    }
  }
}' | jq '[.data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved == false)] | length')

if [[ "$RECHECK" -gt 0 ]]; then
  echo "⚠️ $RECHECK unresolved thread(s) remain. Return to Step 3."
else
  echo "✅ All threads resolved"
fi
```

---

## Step 6: Final CI Check

```bash
gh pr checks "$PR_NUMBER" --watch
```

If CI fails: check logs, fix the issue, re-push, and re-verify.

---

## Step 7: Completion Report

Report in the following format:

```
✅ PR #<number> review processing complete
   Threads handled: N
   Code changes: yes / no
   CI: all checks passed
   Remaining unresolved threads: 0
```

---

## Notes

- Always use **`addPullRequestReviewThreadReply`** (issue comments are not allowed)
- Always resolve after replying (replying without resolving is a violation)
- Process comments from all reviewers including Copilot and book000
- After resolving, check that no new comments were added
