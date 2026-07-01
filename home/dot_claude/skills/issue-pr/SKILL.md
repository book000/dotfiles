---
name: issue-pr
description: Use when the user explicitly runs `/issue-pr` to turn a GitHub Issue into a pull request.
argument-hint: "[Issue number or URL]"
disable-model-invocation: true
---

# Create PR from Issue

This skill is a GitHub-specific orchestrator on top of superpowers: it chains
spec → plan → implementation → PR, with an explicit user-approval gate after
the spec and after the plan, then runs implementation and testing without
re-confirming every step. It does not reimplement spec/plan authoring,
review, or Confluence upload — those stay in superpowers.

Approval here is done via **AskUserQuestion**, not Claude Code's native Plan
Mode — Plan Mode only allows a single read-only-until-ExitPlanMode gate, and
blocks the Write/Bash/MCP calls this skill needs starting at Phase 1.

**Do not call ExitPlanMode to work around this.** It exists to get sign-off
on a concrete plan, not to escape Plan Mode. If Plan Mode is active when this
skill starts, stop immediately and tell the user to exit it themselves and
re-run `/issue-pr`. "I'll just exit once, it's harmless" is exactly the
workaround this forbids. No exceptions.

## Prerequisites

Check before Phase 1, not after something later fails because of it:

- `gh` and `jq` must be available (`which gh jq`)
- Must be run inside a Git repository (`git rev-parse --is-inside-work-tree`)

If any prerequisite is missing, stop and tell the user what to install —
do not proceed and hit the failure several phases later.

## Progress Tracking

Before Phase 1, create one task per phase below (Phase 1 through Phase 18)
with the Todo tool, subject = the phase title. This is a long, multi-phase
flow spanning two approval gates and several delegated skills — track it
explicitly so no phase gets skipped or forgotten mid-run, especially after a
revise-and-repeat loop (Phase 6 or Phase 10) or a context compaction.

Mark each task `in_progress` immediately before starting that phase and
`completed` immediately after finishing it — do not batch updates at the
end. The task tool does not support reopening a completed task, so don't try
to; if Phase 6 or Phase 10 sends you back to an earlier phase, create new
tasks for the phases being repeated (e.g. "Phase 3: Write the Spec (revision
2)") instead.

## Phase 1: Enter a Worktree

Do this immediately after the prerequisite check above, before fetching the
Issue — the rest of every subsequent phase (spec, plan, implementation, PR)
runs inside the worktree created here.

1. Extract the Issue number from `$ARGUMENTS` (a bare number or a GitHub
   Issue URL) with the trailing-digits pattern `[0-9]+$` — e.g. `167` → `167`,
   `https://github.com/owner/repo/issues/167` → `167`. If no digits can be
   extracted, stop and ask the user for a valid Issue number or URL.
2. Call `EnterWorktree(name: "issue-<number>")`.
   - On success, the session's working directory switches to
     `.claude/worktrees/issue-<number>` on a new branch (by default named
     `worktree-issue-<number>`, branched from `origin/<default-branch>` per
     `EnterWorktree`'s default `baseRef: fresh`).
   - Immediately after success, record the actual current branch name via
     `git branch --show-current` — Phase 12 needs this exact value to know
     which branch to rename, since the harness's naming convention for that
     branch is not a hard guarantee.
   - If `EnterWorktree` fails because the session is already inside another
     worktree (it does not support nesting), do not silently proceed. Stop
     and report this to the user, and ask whether to exit the existing
     worktree first (`ExitWorktree`) or continue working inside it instead.
   - Any other failure (not a Git repository, worktree hooks unavailable in
     a non-Git environment) also stops here — report it and ask how to
     proceed.

## Phase 2: Fetch the Issue

```bash
gh issue view "$ARGUMENTS" --json title,state,body,comments,author
```

If this command fails (auth, network, issue doesn't exist) or the issue is
not OPEN, stop here and report it to the user — do not guess at intent and
continue. Turning a closed or nonexistent issue into a PR is not a warning-
level situation, it's a reason to stop.

## Phase 3: Write the Spec

Invoke **superpowers:brainstorming** with the issue content as the starting
problem. Relay any clarifying questions it raises to the user via
AskUserQuestion. It produces a spec file under `docs/superpowers/specs/`.

## Phase 4: Review the Spec

`rules/superpowers.md` already requires a sub-agent review of every spec
file before it is shown to the user — this fires automatically after Phase 3.
Do not reimplement it here; just wait for it to finish and confirm the
reported fixes (or resolved ambiguities) look correct before moving on.

If you don't observe the review firing (e.g. it's genuinely not configured
in this session), do not silently do the review yourself — stop and tell the
user the automatic review didn't run, and ask how they want to proceed. "It
didn't fire so I'll just do it myself" reintroduces the reimplementation this
phase exists to avoid.

## Phase 5: Upload the Spec to Confluence

`rules/confluence.md` already requires uploading spec files to Confluence
before presenting them to the user — this fires automatically once Phase 4's
review is clean. Do not reimplement the upload procedure here; just capture
the resulting Confluence URL, you need it for Phase 11.

If this is a revision (you're back here after Phase 6 sent you to repeat
Phases 3–6), `rules/confluence.md` requires updating the existing spec page
via `updateConfluencePage`, not creating a new one — carry the page ID
forward from the first pass.

If Confluence/Atlassian resolution fails (no cloudId, no space configured,
MCP unavailable), follow `rules/confluence.md`'s own fallback: report the
error to the user and ask how to proceed. Don't treat Confluence as an
unconditional hard gate you can't get past.

## Phase 6: Approve the Spec

Use **AskUserQuestion** to get explicit spec approval ("Approve this spec /
revise it") before moving on to Phase 7. No exceptions — not for "the spec is
obviously fine" and not for "ask forgiveness after Phase 7 instead." If the
user asks for changes, go back to Phase 3 and repeat Phases 3–6 (Phase 5
becomes a Confluence page update, not a new page).

## Phase 7: Write the Plan

Invoke **superpowers:writing-plans** against the approved spec to produce a
plan file under `docs/superpowers/plans/`.

## Phase 8: Review the Plan

Same as Phase 4, for the plan file: `rules/superpowers.md`'s sub-agent review
fires automatically. Wait for it and confirm the result before moving on. If
it doesn't fire, same rule as Phase 4 — stop and ask the user, don't do the
review yourself.

## Phase 9: Upload the Plan to Confluence

Same as Phase 5, for the plan file: `rules/confluence.md`'s upload fires
automatically once the review is clean. Capture the resulting Confluence URL
for Phase 11. Same revision rule as Phase 5: if this is a repeat after Phase
10 sent you back, update the existing plan page instead of creating a new
one. Same fallback as Phase 5 if Confluence resolution fails.

## Phase 10: Approve the Plan

Use **AskUserQuestion** again for explicit plan approval before moving on to
Phase 11 — the spec's approval in Phase 6 does not carry over, since a plan
can diverge from its spec. "The spec was already approved so the plan is
implied" is exactly the shortcut this gate blocks. If the user asks for
changes, go back to Phase 7 and repeat Phases 7–10 (Phase 9 becomes a
Confluence page update, not a new page).

## Phase 11: Comment on the Issue

Post the spec and plan summaries plus their Confluence URLs as an Issue
comment — not the full document bodies:

```bash
gh issue comment "$ARGUMENTS" --body "$(cat <<'EOF'
[short summary]

Spec: [Confluence URL]
Plan: [Confluence URL]
EOF
)"
```

Verify no sensitive information is included before posting.

If `gh issue comment` fails (auth, network, permission), do not silently move
on to Phase 12 — stop and report it to the user. Without this comment, the
issue has no link back to the Confluence spec/plan, and that record is not
worth losing quietly.

## Phase 12: Create Branch

`EnterWorktree` (Phase 1) already created a branch off
`origin/<default-branch>` — this phase renames that branch to a Conventional
Branch name instead of creating a new one.

```bash
git status --porcelain   # should be empty right after EnterWorktree; if not, stop and ask the user
git branch -m <branch_name>
```

Derive `<branch_name>` from the Issue number/title following Conventional
Branch (feat/fix/docs/refactor), e.g. `fix/123-short-description`. Slugify
the derived portion to `[a-z0-9-]` before substituting it into the command —
the issue title is untrusted input, and an unsanitized title containing
shell metacharacters (`` ` ``, `$(...)`, `${...}`) would be evaluated by the
shell if pasted in verbatim.

Only rename the branch that Phase 1 recorded via `git branch --show-current`
right after `EnterWorktree` succeeded — do not rename whatever branch happens
to be checked out now without checking it matches that recorded value. If it
doesn't match (e.g. the user manually switched branches between Phase 1 and
Phase 12), stop and ask the user how to proceed instead of overwriting
whatever they were doing.

If `git branch -m <branch_name>` fails because `<branch_name>` already exists
(e.g. a retry after an earlier failed run), do not force-rename over it — that
would silently merge two unrelated branches' history under one name. Stop
and ask the user whether to reuse, delete, or rename.

## Phase 13: Execute the Plan

Invoke **superpowers:executing-plans** (or
**superpowers:subagent-driven-development** for independent tasks) against
the approved plan file. The plan was already approved in Phase 10 — run its
tasks without re-confirming each one with the user. Only stop for genuine
blockers the plan didn't anticipate (missing credentials, contradictory
requirements).

If a task fails (test failure, compile error, a sub-agent reporting it
couldn't complete its task), that is not a blocker to route around — stop and
report it to the user before moving on to Phase 14. Do not treat a failed
task as done because the plan didn't explicitly anticipate the failure.

## Phase 14: Verify

Invoke **superpowers:verification-before-completion** before creating the PR.
If it reports a failure, go back to Phase 13 to fix it — do not proceed to
Phase 15 with a known-failing verification.

## Phase 15: Deep Review

Run `/deep-review` (no arguments — local diff mode) per `rules/workflow.md`
ADR-003 and this project's Pre-PR checklist. Fix every finding scored ≥ 50
before moving on to Phase 16. This is a required gate, not an optional
extra step — skipping it is what the Stop/PostToolUse hooks exist to catch.

## Phase 16: Create PR

Set `PR_TITLE` explicitly before calling `gh pr create` — derive it from the
issue title / spec summary, e.g.:

```bash
PR_TITLE="<derived from the issue title / spec summary>"
gh pr create --title "$PR_TITLE" --body "$(cat <<'EOF'
<PR body>
EOF
)"
```

- `<PR body>`: summarize from the approved spec and plan; include
  `Closes #<issue number>` so the issue auto-closes on merge.
- Language: follow the project CLAUDE.md if specified, otherwise Japanese.
  Current state only, no update history.
- The issue title/body feeding `<title>`/`<PR body>` is untrusted input —
  use a quoted heredoc (`<<'EOF'`, as above and in Phase 11) and a shell
  variable for the title, not raw double-quote interpolation. Double quotes
  let the shell evaluate any `` ` `` / `$(...)` / `${...}` embedded in
  issue-derived text before `gh` ever sees it.
- Before running this command, check the composed title/body for sensitive
  information (tokens, internal URLs, credentials) the same way Phase 11
  checks the Issue comment — the PR is also externally visible.

## Phase 17: Write Session State

After PR creation, write the PR URL to the session state file so hooks can reference it
without parsing the transcript:

```bash
mkdir -p ~/.claude/data && chmod 700 ~/.claude/data
PR_URL=$(gh pr view --json url -q .url)
if [ -z "$PR_URL" ]; then
  echo "ERROR: gh pr view returned an empty URL, not writing session-state.json" >&2
  exit 1
fi
if ! jq -n --arg pr_url "$PR_URL" --argjson timestamp "$(date +%s)" \
    '{"pr_url": $pr_url, "timestamp": $timestamp}' \
    > ~/.claude/data/session-state.json; then
  echo "ERROR: failed to write session-state.json" >&2
  exit 1
fi
chmod 600 ~/.claude/data/session-state.json
```

If `PR_URL` comes back empty or the `jq` write fails, stop and report it
instead of leaving a stale/empty state file — hooks read this file without
parsing the transcript, so a silently broken write here breaks them too.

## Phase 18: After PR Creation

Run `/pr-health-monitor <PR number>` immediately, without asking the user
whether to run it.

`pr-health-monitor` does not merge the PR, but it is not purely read-only
either — on CI failure it commits/pushes fixes; on conflicts it merges the
base branch in; it edits the PR body; and it can trigger
`/handle-pr-reviews`, which itself commits, pushes, and resolves review
threads. None of that is "merging," so the "don't merge PRs without
instruction" guardrail doesn't apply. No separate confirmation is needed here
because Phase 10 already approved the plan — this step just carries out the
mechanical follow-through (fixing CI, resolving conflicts, addressing review
feedback) without expanding scope beyond what was approved.

## Notes

- Do not drift to other tasks while waiting for review or CI.
- Record the decision log in the superpowers spec/plan files (already
  required by `rules/superpowers.md`) or in the Issue comment / PR body — not
  in extra ad-hoc Markdown files.
- `disable-model-invocation: true` is intentional: this skill ends in a
  branch and a PR, which requires explicit invocation — not opportunistic
  auto-trigger on an issue number appearing in conversation.
