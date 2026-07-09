---
name: issue-pr-lite
description: Lightweight path for small-scale Issues. Invoked by the `issue-pr` dispatcher after Phase 2.5 judges the change small-scale and the user confirms. Skips spec/plan; implements directly.
disable-model-invocation: true
---

# issue-pr-lite: lightweight implementation path

> **Note:** Invoked by the `issue-pr` dispatcher after its Phase 1
> (worktree), Phase 2 (Issue fetch), and Phase 2.5 (scale judgment)
> complete. Assumes `ISSUE_OWNER`, `ISSUE_REPO`, the Issue body, and the
> active worktree are already established in context. If invoking this
> skill standalone, perform the equivalent of dispatcher Phase 1/2 first.

This is the lightweight counterpart to `issue-pr-deep`: no spec, no plan,
no approval gates. Implementation proceeds directly from the Issue body.

## Progress Tracking

Before Phase 3, create one Todo task per phase in this file (Phase 3
through the end) using the Todo tool. Mark each `in_progress` immediately
before starting that phase and `completed` immediately after finishing it —
do not batch updates at the end.

## Phase 3: Implement Directly

Read the Issue body already fetched by the dispatcher. Implement the
change directly — do not invoke `superpowers:brainstorming`,
`superpowers:writing-plans`, or `superpowers:executing-plans` (there is no
plan document to execute against).

If, while implementing, you discover the change is more involved than the
dispatcher's Phase 2.5 judgment assumed (e.g. it turns out to require a
design decision), stop and tell the user — do not silently keep going down
the lite path if it no longer fits. Recommend switching to `issue-pr-deep`.

## Phase 4: Create Branch

Same logic as `issue-pr-deep`'s Phase 11 (branch rename from the
dispatcher-created worktree branch to a Conventional Branch name):

```bash
git status --porcelain   # should be empty right after EnterWorktree; if not, stop and ask the user
git branch -m <worktree_branch_name> <branch_name>
```

Derive `<branch_name>` from the Issue number/title following Conventional
Branch (feat/fix/docs/refactor), slugified to `[a-z0-9-]`.
`<worktree_branch_name>` is the value the dispatcher recorded in its
Phase 1. Use the explicit two-argument form of `git branch -m`; if it
fails because `<branch_name>` already exists, stop and ask the user how
to proceed.

## Phase 5: Verify

Invoke **superpowers:verification-before-completion** before creating the
PR. If it reports a failure, fix it and re-run before moving on.

## Phase 6: Lite Review

Run `/lite-review` (no arguments — local diff mode). Fix every finding
scored ≥ 50 before moving on to Phase 7. This replaces `issue-pr-deep`'s
Phase 14 `/deep-review` gate — the lite path always uses `/lite-review`.

## Phase 7: Create PR

Same logic as `issue-pr-deep`'s Phase 15, with one difference: the PR body
does **not** include `Spec: [URL]` / `Plan: [URL]` lines (no spec/plan
document exists for this path).

```bash
git push -u origin "$(git branch --show-current)"
```

```bash
PR_TITLE="<derived from the issue title>"
gh pr create --repo "$ISSUE_OWNER/$ISSUE_REPO" --title "$PR_TITLE" --body "$(cat <<'PRBODY'
<PR body — summarize from the Issue body; include `Closes #<issue number>`; no Spec/Plan lines>
PRBODY
)"
```

Same untrusted-input precautions as `issue-pr-deep`'s Phase 15 (quoted
heredoc, sensitive-info check, `--repo` explicit).

## Phase 8: Write Session State

Same as `issue-pr-deep`'s Phase 16, verbatim:

```bash
mkdir -p ~/.claude/data && chmod 700 ~/.claude/data
PR_URL=$(gh pr view --repo "$ISSUE_OWNER/$ISSUE_REPO" --json url -q .url)
if [ -z "$PR_URL" ]; then
  echo "ERROR: gh pr view returned an empty URL, not writing session-state.json" >&2
  exit 1
fi
if ! jq -n --arg pr_url "$PR_URL" --arg session_id "${CLAUDE_CODE_SESSION_ID:-}" --argjson timestamp "$(date +%s)" \
    '{"pr_url": $pr_url, "session_id": $session_id, "timestamp": $timestamp}' \
    > ~/.claude/data/session-state.json; then
  echo "ERROR: failed to write session-state.json" >&2
  exit 1
fi
chmod 600 ~/.claude/data/session-state.json
```

## Phase 9: After PR Creation

Same as `issue-pr-deep`'s Phase 17: run `/pr-health-monitor <PR number>`
immediately, without asking the user whether to run it.

## Phase 10: Start the PR Close Monitor

Same as `issue-pr-deep`'s Phase 18:

```bash
PR_NUMBER=$(gh pr view --repo "$ISSUE_OWNER/$ISSUE_REPO" --json number -q .number)
```

Then follow `wait-for-pr-close`'s own SKILL.md (Step 0 already-closed state
check, then `Monitor(..., persistent: true)`), always passing `--repo
"$ISSUE_OWNER/$ISSUE_REPO"` explicitly (fork scenario safety — see
`issue-pr-deep`'s Phase 18 for the full rationale). When the monitor emits a
`pr_closed` event, call `/pr-cleanup` directly in this same conversation.
