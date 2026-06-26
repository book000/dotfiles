---
name: wait-for-copilot-review
description: Waits in the background for a GitHub Copilot review after PR creation and automatically triggers /handle-pr-reviews on detection.
argument-hint: "[PR number]"
disable-model-invocation: true
---

# Wait for GitHub Copilot Review

Automatically detects and notifies when GitHub Copilot posts a review after PR creation.

## Usage

```bash
/wait-for-copilot-review <PR_NUMBER>
```

Or run the script directly:

```bash
${CLAUDE_SKILL_DIR}/scripts/wait-for-copilot-review.sh <PR_NUMBER> &
```

## Features

### Detection Logic

- **Primary**: checks whether `author.__typename` is `Bot` via GraphQL API
- **Secondary**: checks whether `author.login` contains `copilot` (supplementary)
- **Check interval**: 30 seconds
- **Max wait time**: 30 minutes (60 checks)

### Detection Conditions

A review is detected as a Copilot review when **all** of the following are true:

1. `author.__typename` is `"Bot"`
2. `author.login` contains `"copilot"` (partial match)
3. `state` is `"COMMENTED"` or `"APPROVED"`
4. `submittedAt` is not null (completed reviews only)

### Background Execution

- **Log file**: `~/.claude/logs/wait-copilot-review-<PR_NUMBER>.log`
- **Lock file**: `~/.claude/locks/wait-copilot-review-<PR_NUMBER>.lock`
- **Mutual exclusion**: flock prevents multiple concurrent instances

### On Detection

1. Notify the user (via Discord notification script)
2. Display the review comment count
3. Record detection result to log

## GraphQL Query

```graphql
query($owner: String!, $repo: String!, $number: Int!) {
  repository(owner: $owner, name: $repo) {
    pullRequest(number: $number) {
      reviews(first: 100) {
        nodes {
          author {
            login
            __typename
          }
          state
          submittedAt
        }
      }
    }
  }
}
```

## Notes

- Maximum wait time is 30 minutes
- If timed out, the review may still be posted later
- Multiple instances are automatically prevented by flock
- Check the log file for execution status

## Troubleshooting

### Check Logs

```bash
tail -f ~/.claude/logs/wait-copilot-review-<PR_NUMBER>.log
```

### Remove Lock File (emergency only)

```bash
rm ~/.claude/locks/wait-copilot-review-<PR_NUMBER>.lock
```

### Manually Check Review

```bash
gh api graphql -f owner="$OWNER" -f repo="$REPO" -F number=<PR_NUMBER> -f query='
query($owner: String!, $repo: String!, $number: Int!) {
  repository(owner: $owner, name: $repo) {
    pullRequest(number: $number) {
      reviews(first: 100) {
        nodes {
          author {
            login
            __typename
          }
          state
          submittedAt
        }
      }
    }
  }
}' --jq '.data.repository.pullRequest.reviews.nodes[] | select(.author.__typename == "Bot" and (.author.login | contains("copilot")))'
```
