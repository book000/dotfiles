---
name: pr-health-monitor
description: Automates the post-PR monitoring workflow. Runs CI check, Copilot review wait, code review, conflict check, and PR body update in parallel. Use with /pr-health-monitor <PR number or URL> immediately after creating a PR.
argument-hint: "[PR number or URL]"
disable-model-invocation: false
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

**Use the Task tool to run all of the following in parallel.** Do not ask
the user for confirmation before starting any of these — they are the
mechanical follow-through of an already-approved PR creation, not new
decisions.

### Task A: Request Copilot Review → Monitor-Based Wait

```bash
# Request review from Copilot
request-review-copilot "https://github.com/${OWNER}/${REPO}/pull/${PR_NUMBER}"
```

Then start the Copilot review monitor following `wait-for-copilot-review`'s
own SKILL.md (Step 0 existence check, then `Monitor(..., persistent: true)`).
On detection, call `/handle-pr-reviews` directly in this conversation — no
tmux, no background process.

### Task B: CI Check (Monitor-Based)

```bash
Monitor({
  command: "
    prev=\"\"
    fail_count=0
    while true; do
      s=$(gh pr checks \"$PR_NUMBER\" --json name,bucket 2>/dev/null || true)
      if [[ -z \"$s\" ]]; then
        fail_count=$((fail_count + 1))
        if [[ \"$fail_count\" -ge 5 ]]; then
          echo \"WARNING: gh pr checks failed 5 times in a row (auth or network issue?)\"
          fail_count=0
        fi
      else
        fail_count=0
      fi
      cur=$(jq -r '.[] | select(.bucket!=\"pending\") | \"\\(.name): \\(.bucket)\"' <<<\"$s\" 2>/dev/null | sort)
      if [[ -n \"$cur\" && \"$cur\" != \"$prev\" ]]; then
        comm -13 <(echo \"$prev\") <(echo \"$cur\")
      fi
      prev=\"$cur\"
      jq -e 'all(.bucket!=\"pending\")' <<<\"$s\" >/dev/null 2>&1 && { echo \"ci_complete\"; break; }
      sleep 30
    done
  ",
  description: "CI checks on PR #<PR_NUMBER>",
  persistent: true,
})
```

`fail_count` により、`gh pr checks` が5回連続（約2分半）で失敗した場合に
Monitor の標準出力へ警告を1行出力する（同上の要件への対応）。

If any emitted line shows a `fail` bucket:
1. Check logs with `gh run view <RUN_ID> --log-failed`
2. Identify the cause and fix it
3. Commit, push, and restart this Monitor to watch the re-run

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
⏳ Copilot review: Monitor running in this session
   → /handle-pr-reviews will be called directly in this conversation on detection
```

---

## Phase 2: After Copilot Review Detection (auto-triggered)

When the Copilot review Monitor (Task A) emits a `copilot_review_detected`
event, call `/handle-pr-reviews` directly in this conversation:

```
/handle-pr-reviews https://github.com/OWNER/REPO/pull/PR_NUMBER
```

This automatically replies to all review threads, resolves them, and does
a final CI check. No tmux involved — the event and the follow-up call both
happen in the same conversation.

---

## Notes

- Skip `request-review-copilot` if the command does not exist
- Both Copilot review and CI checks run as `Monitor(persistent: true)`
  instances in this session — if the session ends before either completes,
  the wait is lost and must be resumed manually later
- CI can take a long time — always use the Task tool to run it in parallel
  alongside the other Monitor-based waits
