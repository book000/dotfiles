---
name: issue-pr-lite
description: Lightweight path for small-scale Issues. Invoked by the `issue-pr` dispatcher after Phase 2.5 judges the change small-scale. Skips spec/plan; implements directly.
disable-model-invocation: false
---

# issue-pr-lite: lightweight implementation path

> **Note:** Invoked by the `issue-pr` dispatcher after its Phase 1
> (worktree), Phase 2 (Issue fetch), and Phase 2.5 (scale judgment)
> complete. Assumes `ISSUE_OWNER`, `ISSUE_REPO`, the Issue body, and the
> active worktree are already established in context. If invoking this
> skill standalone, perform the equivalent of dispatcher Phase 1/2 first.

This is the lightweight counterpart to `issue-pr-deep`: no spec, no plan,
no approval gates. Implementation proceeds directly from the Issue body.

Before Phase 3, Read `~/.claude/docs/design-workflow.md` (not auto-loaded); its Final Evidence Gate section is cited below.

## Progress Tracking

Before Phase 3, create one Todo task per phase in this file (Phase 3
through the end) using the Todo tool. Mark each `in_progress` immediately
before starting that phase and `completed` immediately after finishing it —
do not batch updates at the end.

## Phase 3: Implement Directly

Read the Issue body already fetched by the dispatcher. Implement the
change directly — this path has no Spec/Plan authoring phase to execute
against.

If, while implementing, you discover the change is more involved than the
dispatcher's Phase 2.5 judgment assumed (e.g. it turns out to require a
design decision), stop and tell the user — do not silently keep going down
the lite path if it no longer fits. Recommend switching to `issue-pr-deep`.

## Phase 4: Create Branch

Same logic as `issue-pr-deep`'s Phase 10 (branch rename from the
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

Follow `~/.claude/docs/design-workflow.md`'s Final Evidence Gate (Prompt-Only
Contract) before creating the PR: record snapshot `S` (`HEAD`, staged
state, tracked working-tree diff, untracked files, and the identity of the
verification evidence collected so far), then run a fresh full
verification. Carry the same gate discipline into Phase 6 (Lite Review) —
re-confirm the working tree still matches `S` before each subsequent step,
restart the whole gate from scratch if anything changes, and never treat a
sub-agent's own "done" or "tests pass" self-report as completion evidence.

## Phase 6: Lite Review

Run `/lite-review` (no arguments — local diff mode). Resolve every
verified merge-blocker finding before moving on to Phase 7. In local diff
mode `/lite-review` uses the ledger in review mode, so the hooks do not
block on open merge-blockers and `ledger.sh count-open-blockers` always
returns 0; the gate is therefore explicit. After `/lite-review` returns,
count the open merge-blocker findings in its ledger by running
`~/.agents/skills/deep-review/scripts/ledger.sh show "${CLAUDE_SESSION_ID}" | jq '[.findings[] | select(.class == "merge-blocker" and .status == "open")] | length'`.
Do not proceed to Phase 7 while the count is non-zero: fix the findings and
re-run `/lite-review` (it creates a fresh ledger) until the count is 0. If
the count cannot be read, stop and report to the user. This replaces
`issue-pr-deep`'s Phase 13 `/deep-review` gate — the lite path always uses
`/lite-review`. This is a deliberate, user-approved exception to the global
pre-PR rule of running `/deep-review --fix`.

## Phase 7: Create PR

Same logic as `issue-pr-deep`'s Phase 14, with one difference: the PR body
does **not** include `Spec: [URL]` / `Plan: [URL]` lines (no spec/plan
document exists for this path).

```bash
git push -u origin "$(git branch --show-current)"
```

Draft or regular: apply the same criterion as `issue-pr-deep`'s Phase 14 (set `DRAFT=1` for a draft, empty otherwise) and pass `${DRAFT:+--draft}`; the ready decision is made later by `/pr-health-monitor`.

book000 is requested as the PR reviewer via `gh-pr-reviewer.sh` (empty output means skip the
`--reviewer` flag). If the helper exits non-zero, stop before creating the PR and report the failure.

```bash
PR_TITLE="<derived from the issue title>"
REVIEWER=$(gh-pr-reviewer.sh "$ISSUE_OWNER/$ISSUE_REPO")
DRAFT=1  # set to empty for a regular (non-draft) PR
gh pr create --repo "$ISSUE_OWNER/$ISSUE_REPO" ${DRAFT:+--draft} ${REVIEWER:+--reviewer "$REVIEWER"} --title "$PR_TITLE" --body "$(cat <<'PRBODY'
<PR body — summarize from the Issue body; include `Closes #<issue number>`; no Spec/Plan lines>
PRBODY
)"
```

Same untrusted-input precautions as `issue-pr-deep`'s Phase 14 (quoted
heredoc, sensitive-info check, `--repo` explicit).

## Phase 8: Write Session State

Same as `issue-pr-deep`'s Phase 15:

```bash
write-session-state.sh "$ISSUE_OWNER/$ISSUE_REPO"
```

The script prints the PR URL on success; use that value as `PR_URL` in the
next phase. If it exits non-zero (empty URL or failed `jq` write), stop and
report it instead of leaving a stale/empty state file.

## Phase 9: After PR Creation

Same as `issue-pr-deep`'s Phase 16: pass the `PR_URL` resolved above (not a bare number, which would be re-resolved via `gh-pr-target-repo.sh` and can pick the wrong repository) and run `/pr-health-monitor "$PR_URL"` immediately, without asking the user whether to run it. Its unified Monitor handles review feedback, CI, conflicts and `pr_closed` (running `/pr-cleanup`) in this conversation; do not pause to ask the user whether to keep waiting for a Copilot review.

The `issue-pr-lite` flow is considered complete once `pr-health-monitor` has started the Monitor.
