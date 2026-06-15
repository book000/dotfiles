---
name: pr-health-monitor
description: Automates the post-PR monitoring workflow. Runs CI check, Copilot review wait, code review, conflict check, and PR body update in parallel. Use with /pr-health-monitor <PR number or URL> immediately after creating a PR.
argument-hint: "[PR number or URL]"
---

# PR Health Monitor

Automates the full post-PR checklist.

## Usage

```
/pr-health-monitor <PR number or URL>
```

**Examples:**
- `/pr-health-monitor 123`
- `/pr-health-monitor https://github.com/owner/repo/pull/123`

---

## Step 0: Resolve PR Info

Resolve OWNER, REPO, and PR number from the argument.

```bash
# URL format: grep -oP does not support capture groups, so extract each field separately
PR_ARG="$ARGUMENTS"
if echo "$PR_ARG" | grep -q 'github\.com'; then
  OWNER=$(echo "$PR_ARG" | grep -oP 'github\.com/\K[^/]+')
  REPO=$(echo "$PR_ARG" | grep -oP 'github\.com/[^/]+/\K[^/]+(?=/pull)')
  PR_NUMBER=$(echo "$PR_ARG" | grep -oP '/pull/\K\d+')
else
  # Number only (get from current repository)
  OWNER=$(gh repo view --json owner --jq '.owner.login')
  REPO=$(gh repo view --json name --jq '.name')
  PR_NUMBER="$PR_ARG"
fi
```

Confirm the PR URL:

```bash
gh pr view "$PR_NUMBER" --json url --jq '.url'
```

---

## Step 1: Parallel Execution Phase

**Use the Task tool to run all of the following in parallel.**

### Task A: Request Copilot Review → Background Wait

```bash
# Request review from Copilot
request-review-copilot "https://github.com/${OWNER}/${REPO}/pull/${PR_NUMBER}"

# Wait for Copilot review in the background
# On detection, /handle-pr-reviews is automatically triggered via tmux
~/.claude/skills/wait-for-copilot-review/scripts/wait-for-copilot-review.sh "$PR_NUMBER" &
echo "Copilot review wait started (background)"
echo "Log: ~/.claude/logs/wait-copilot-review-${PR_NUMBER}.log"
```

### Task B: CI Check

```bash
gh pr checks "$PR_NUMBER" --watch
```

If CI fails:
1. Check logs with `gh run view <RUN_ID> --log-failed`
2. Identify the cause and fix it
3. Commit, push, and wait until CI passes again

### Task C: Conflict Check

```bash
gh pr view "$PR_NUMBER" --json mergeable,mergeStateStatus --jq '{mergeable,mergeStateStatus}'
```

If there are conflicts, merge the base branch to resolve them.

### Task D: Update PR Body

Following CLAUDE.md rules, write the PR body with the current final state of the branch only — no history. Language: follow the project CLAUDE.md if it specifies one; otherwise Japanese.

```bash
gh pr edit "$PR_NUMBER" --body "$(cat <<'BODY'
## Summary
(or ## 概要 if project language is Japanese)

...

## Changes
(or ## 変更内容 if project language is Japanese)

...
BODY
)"
```

## Step 2: Completion Report

Report the result of each task in the following format:

```
✅ CI: all checks passed
✅ Conflicts: none
✅ PR body: updated
⏳ Copilot review wait: continuing in background
   → /handle-pr-reviews will be triggered automatically on detection
   → Log: ~/.claude/logs/wait-copilot-review-<PR_NUMBER>.log
```

---

## Phase 2: After Copilot Review Detection (auto-triggered)

When the background script detects a Copilot review, the following is automatically triggered via tmux:

```
/handle-pr-reviews https://github.com/OWNER/REPO/pull/PR_NUMBER
```

This automatically replies to all review threads, resolves them, and does a final CI check.

---

## Notes

- Skip `request-review-copilot` if the command does not exist
- If no Copilot review arrives within 30 minutes, the script times out and sends a tmux notification
- CI can take a long time — always use the Task tool to run it in parallel
