---
name: issue-pr-deep
description: Spec-approval and plan-review flow for turning a GitHub Issue into a pull request. Invoked by the `issue-pr` dispatcher for non-trivial changes.
disable-model-invocation: false
---

# issue-pr-deep: spec-approval and plan-review flow

> **Note:** This skill is invoked by the `issue-pr` dispatcher after its
> Phase 1 (worktree) and Phase 2 (Issue fetch) complete. It assumes
> `ISSUE_OWNER`, `ISSUE_REPO`, the Issue body, and the active worktree are
> already established in context — it does not redo them. If invoking this
> skill standalone, perform the equivalent of dispatcher Phase 1/2 first.
>
> Phases below (5, 9) still refer to the Issue number/URL via `$ARGUMENTS`,
> the same variable the dispatcher's own Phase 1/2 used. Since this skill is
> reached via the Skill tool rather than as a top-level slash-command
> invocation, `$ARGUMENTS` is not automatically re-bound here — the
> dispatcher must pass the Issue number/URL it extracted in its own Phase 1
> explicitly when invoking this skill, and this skill must treat that value
> as `$ARGUMENTS` for the rest of its phases.

## Progress Tracking

Before Phase 3, create one Todo task per phase in this file (Phase 3
through the end) using the Todo tool. Mark each `in_progress` immediately
before starting that phase and `completed` immediately after finishing it —
do not batch updates at the end.

If a revise loop (Phase 6) sends execution back to an earlier phase, create
a **new** task for the repeated phase (e.g. "Phase 3: Write the Spec
(revision 2)") rather than reopening the completed one. There is no
equivalent revise loop for the plan — the plan has no human approval step.

Once a phase's task is marked `completed`, immediately mark the next
phase's task `in_progress` in the same turn and start that work — do not
end the turn after marking `completed` and defer starting the next task.

## Phase Transition Self-Check

Every phase boundary in this file, except an explicit `AskUserQuestion`
approval gate (Phase 6) or an explicitly written failure/stop condition, is
an "auto-continue point" — this applies to every phase boundary in this
file, not just Phase 3→4.

Actions that must never happen at an auto-continue point:

- Ending the turn after issuing a completion-report sentence such as "I
  did X" / "X is complete."
- Waiting for a user response like "go ahead" / "proceed" / "OK."
- Inserting a content-free "may I proceed?" confirmation.

Noticing you are about to do any of the above is itself a bug —
self-correct immediately in the same turn and proceed into the next
phase's work.

## Phase 3: Write the Spec

Author the spec yourself, following `rules/design-workflow.md`'s Intent
Contract, Fact / Decision Separation, Decision Dependency / Frontier,
Alternative Exploration, and Spec Synthesis sections:

- **Intent Contract**: establish Outcome, Success criteria, Scope,
  Non-goals, Constraints, Accepted facts, Assumptions, and Remaining
  unknowns. Skip anything the Issue body already states clearly — read it
  first.
- **Fact / Decision Separation**: a Fact is anything confirmable from the
  repository, official documentation, or a command/test/PoC — investigate
  these yourself (repo search, docs, tests, official sources); never ask
  the user about a Fact. A Decision is a product requirement, UX
  preference, trade-off, scope boundary, or irreversible policy choice —
  these are the only things AskUserQuestion is for.
- **Decision Dependency / Frontier**: batch every independent Decision into
  a single AskUserQuestion round instead of asking one at a time; never
  ask a dependent Decision before its prerequisite is resolved.
- **Alternative Exploration**: only compare multiple approaches when
  materially different designs actually exist; the simplest approach that
  satisfies the Intent Contract wins by default (YAGNI).
- **Spec Synthesis**: once the Decision frontier is empty, synthesize the
  answers into one coherent spec covering the sections listed in
  `rules/design-workflow.md`'s Spec Synthesis section, with an Acceptance
  Criteria section that is observable/testable, not aspirational prose.

Write the spec to `.agent-work/specs/YYYY-MM-DD-<topic>-design.md`.

Write the spec document's body in the language required by the target
project's CLAUDE.md (for this repository, Japanese — `会話は日本語で行う`);
code blocks/commands/identifiers may stay as-is. Do not assume this is
inferred from context.

Do not ask a content-free "may I proceed" confirmation before or during
this phase. Genuine requirement-clarifying questions (real ambiguity in the
Issue's request, i.e. a genuine Decision) are fine via AskUserQuestion;
asking permission with no new information is not. The sole human
checkpoint for the spec's content is Phase 6, after the spec is posted as
an Issue comment.

Per `rules/design-workflow.md`'s Local-Only Artifacts policy, `.agent-work/`
is `.gitignore`d — do not `git add -f` the spec file.

Once the spec file is written, proceed immediately into Phase 4 below
without waiting for the user or announcing a stop — this flow's own
Phase 4 through Phase 6 own spec review, posting, and approval.

## Phase 4: Review the Spec

`rules/design-workflow.md`'s Spec Review Contract requires dispatching the
`spec-reviewer` sub-agent (`Agent` tool, `subagent_type: spec-reviewer`)
against the spec file. Dispatch it now, wait for it, and confirm the
reported fixes/ambiguities look correct before moving on.

If the dispatch fails or the sub-agent cannot run, do not skip the review
yourself — stop and tell the user, and ask how to proceed.

## Phase 5: Post the Spec as an Issue Comment

`rules/issue-comment-docs.md` covers this case (the spec is tied to this
Issue) — follow its procedure directly:

```bash
url=$(gh issue comment "$ARGUMENTS" --repo "$ISSUE_OWNER/$ISSUE_REPO" --body-file <spec-file-path>)
SPEC_COMMENT_URL="$url"
SPEC_COMMENT_ID=${url##*issuecomment-}
```

Capture `SPEC_COMMENT_URL`/`SPEC_COMMENT_ID` (needed for Phase 6 and any
later revision).

If this is a revision (Phase 6 sent you back), update the existing comment
by its ID instead of creating a new one:

```bash
gh api "repos/$ISSUE_OWNER/$ISSUE_REPO/issues/comments/$SPEC_COMMENT_ID" -X PATCH -F body=@<spec-file-path>
```

Do not use `--edit-last` — it targets the current user's last comment on
the whole Issue, which could silently overwrite the plan's comment (Phase 9)
if posted first.

If `gh issue comment` / `gh api` fails, follow
`rules/issue-comment-docs.md`'s fallback: report it and ask how to proceed.

## Phase 6: Approve the Spec

Use **AskUserQuestion** to get explicit spec approval before Phase 7. No
exceptions for "obviously fine" or asking forgiveness afterward.

The question text MUST include `SPEC_COMMENT_URL` from Phase 5 (if that post
failed and fell back, report that first). Fix the options to exactly these
two (AskUserQuestion's `options` requires ≥2 entries):

- "承認する" (Approve)
- "修正してほしい(Otherで内容を指示)" (Revise — specify what via Other)

If revise is chosen, get what to change via the "Other" free-text field,
update the spec, and repeat Phases 3–6 (Phase 5 becomes an update via
`SPEC_COMMENT_ID`, not a new comment).

## Phase 7: Write the Plan

Author the plan yourself against the approved spec, following
`rules/design-workflow.md`'s Plan Generation Contract: each task needs at
minimum Files (Create/Modify/Test), Depends on, Change, Contracts/
Invariants, a concrete Verification command with expected evidence, Stop
Conditions, and Assumptions.

Size tasks so each is independently verifiable and has clear dependencies —
not so large it hides multiple decisions, not so small it becomes
bureaucratic overhead. Do not force uniform micro-stepping, and do not
embed full production/test code in the plan except where a signature,
schema, migration command, external API shape, or rollback command is
fragile enough that paraphrasing it would break it — record those exact
values.

Write the plan to `.agent-work/plans/YYYY-MM-DD-<topic>.md`.

Same language instruction as Phase 3 (Japanese for this repository, code/
commands/identifiers as-is), and same Local-Only Artifacts rule — the plan
stays a local untracked artifact under `.agent-work/`, never `git add -f`.

This flow decides the execution approach itself in Phase 11, without
asking the user — do not raise an execution-approach question here
either, and proceed directly from plan completion into Phase 8 with no
confirmation, no waiting for a response.

## Phase 8: Review the Plan

`rules/design-workflow.md`'s Plan Review Contract requires dispatching the
`plan-reviewer` sub-agent (`Agent` tool, `subagent_type: plan-reviewer`)
against the plan file. Dispatch it now, wait for it, and confirm the
reported fixes look correct before moving on.

If the dispatch fails or the sub-agent cannot run, do not skip the review
yourself — stop and tell the user, and ask how to proceed.

## Phase 9: Post the Plan as an Issue Comment

Same as Phase 5, for the plan file — follow `rules/issue-comment-docs.md`
directly:

```bash
url=$(gh issue comment "$ARGUMENTS" --repo "$ISSUE_OWNER/$ISSUE_REPO" --body-file <plan-file-path>)
PLAN_COMMENT_URL="$url"
PLAN_COMMENT_ID=${url##*issuecomment-}
```

This must be a **new** comment, never reusing `SPEC_COMMENT_ID`. Posted for
record/audit purposes — Phase 8's dispatched `plan-reviewer` review already
ran before this posting, and there is no human approval step for the plan
(see Notes for why), so this comment is not revised afterward.

Same fallback as Phase 5 if the post fails.

## Phase 10: Create Branch

`EnterWorktree` (Phase 1) already created a branch off
`origin/<default-branch>`; this phase renames it to a Conventional Branch
name instead of creating a new one.

```bash
git status --porcelain   # should be empty right after EnterWorktree; if not, stop and ask the user
git branch -m <worktree_branch_name> <branch_name>
```

Derive `<branch_name>` from the Issue number/title following Conventional
Branch (feat/fix/docs/refactor), e.g. `fix/123-short-description`. Slugify
it to `[a-z0-9-]` before substituting — the issue title is untrusted input
and could contain shell metacharacters (`` ` ``, `$(...)`, `${...}`).

`<worktree_branch_name>` is the value Phase 1 recorded via
`git branch --show-current`. Always use the two-argument form of
`git branch -m`, never the one-argument form (renames whatever is checked
out). If it no longer matches the current `git branch --show-current`,
stop and ask how to proceed.

If `git branch -m <branch_name>` fails because it already exists, do not
force-rename over it — stop and ask whether to reuse, delete, or rename.

## Phase 11: Execute the Plan

Decide the execution approach yourself, per `rules/design-workflow.md`'s
Implementation Execution section: this defers to the existing decision
framework in `rules/workflow-sub-agents.md` as-is — main-agent-direct for
tightly sequential, high-context-dependency, or few-file work; sub-agent
dispatch for genuinely independent, specialized, or context-isolation-
benefiting work. Do not ask the user to choose. This decision must already
be final by the time this phase starts: if you find yourself about to ask
the user which approach to use, that is a bug in this flow, not a
legitimate checkpoint. Move from plan completion directly into execution,
with no pause, no confirmation, and no waiting for a response before
starting.

Execute the plan's tasks directly (or via dispatched sub-agents, per the
decision above) without re-confirming each one with the user; only stop
for genuine blockers the plan didn't anticipate (missing credentials,
contradictory requirements) — see `rules/design-workflow.md`'s Stop
Conditions section.

If a task fails (test failure, compile error, a sub-agent reporting it
couldn't complete), stop and report it before moving to Phase 12 — do not
treat it as done.

## Phase 12: Verify

Run `rules/design-workflow.md`'s Final Evidence Gate (Prompt-Only Contract)
before creating the PR:

1. Record a snapshot `S` of: `HEAD`, staged state, tracked working-tree
   diff, untracked files, and the identity of the verification evidence
   collected so far.
2. Re-confirm the working tree still matches `S` while progressing
   through, in order: fresh full verification → secret check → Phase 13's
   `/deep-review --fix` → diff/status/evidence check → a final check immediately
   before commit/PR.
3. If anything changes partway through this sequence, restart the whole
   gate from scratch rather than patching around the drift.
4. A sub-agent's own "done" or "tests pass" self-report is never itself
   completion evidence — inspect the evidence directly.

If any step reports a failure, go back to Phase 11 to fix it — do not
proceed to Phase 13 with a known-failing verification.

## Phase 13: Deep Review

Dispatch a `general-purpose` sub-agent with the `Agent` tool as a **sync dispatch** (do not pass `run_in_background`) — Phase 13 and Phase 14 are strictly sequential, and there is no other independent work to run alongside it, so `rules/workflow-sub-agents.md`'s decision table calls for sync here. Do not set `isolation`: the sub-agent must run in the current worktree, the same one the parent has been working in.

Give the sub-agent's dispatch prompt:

- It is working in the current worktree (no `isolation`, so it shares the
  parent's cwd and git state).
- It must run `/deep-review --fix` (local diff mode; fix mode edits the
  working tree and does not commit) per `rules/workflow.md` ADR-003.
- Its final report to the parent must include: the `$CLAUDE_SESSION_ID` it
  ran under, and the output of
  `~/.agents/skills/deep-review/scripts/ledger.sh
  count-open-blockers <that SID>` (the integer count of open merge-blocker
  findings).

Because this dispatch uses the `Agent` tool rather than the `Skill` tool, the PostToolUse/Stop hooks that normally enforce ADR-003 do not fire for it (they key off the `Skill` tool call and the parent's own session id — see the spec's Constraints & Established Facts). This step's own completion check substitutes for that automatic block: **the parent must not proceed to Phase 14 until the sub-agent's final report shows an open merge-blocker count of 0.** If the count is not 0, or the report omits it, treat Phase 13 as incomplete — do not proceed to Phase 14; report the outstanding count and the ledger session id to the user instead.

After receiving the sub-agent's report, the parent session must independently run `~/.agents/skills/deep-review/scripts/ledger.sh count-open-blockers <SID>` itself via Bash, using the session ID from the report, and gate progression to Phase 14 on that independently-obtained count rather than on the sub-agent's stated figure. If the two counts disagree, or the independently-obtained count is nonzero, do not proceed to Phase 14 — report the discrepancy or the outstanding blockers to the user instead.

If the sync `Agent` call itself errors, or its report is missing the required session ID or blocker count, re-dispatch once (a second sync `Agent` call with the same instructions). If that second attempt also fails or is incomplete, stop and report to the user per `rules/design-workflow.md`'s Stop Conditions item 6 ("A required tool or sub-agent invocation fails with no safe automatic recovery, and only a human can decide how to proceed") — do not reference `rules/workflow-sub-agents.md`'s background-only nudge/re-dispatch idle-notification procedure here, since that procedure is explicitly scoped to background-mode sub-agent dispatches and this is a sync dispatch.

## Phase 14: Create PR

`gh pr create` requires the branch to already exist on a remote. Push it
first, or it fails with `aborted: you must first push the current branch to
a remote, or use the --head flag`:

```bash
git push -u origin "$(git branch --show-current)"
```

(In the fork scenario, `origin` is the local checkout's own remote, not
`$ISSUE_OWNER/$ISSUE_REPO`.)

Set `PR_TITLE` explicitly before calling `gh pr create` — derive it from the
issue title / spec summary, e.g.:

```bash
PR_TITLE="<derived from the issue title / spec summary>"
gh pr create --repo "$ISSUE_OWNER/$ISSUE_REPO" --title "$PR_TITLE" --body "$(cat <<'EOF'
<PR body>
EOF
)"
```

- `<PR body>`: summarize from the approved spec/plan; include
  `Closes #<issue number>`, plus the Spec/Plan comment URLs
  (`SPEC_COMMENT_URL`, `PLAN_COMMENT_URL`) in this exact format:

  ```
  Spec: [Issue comment URL]
  Plan: [Issue comment URL]
  ```

- Language: follow the project CLAUDE.md if specified, otherwise Japanese.
  Current state only, no update history.
- Issue title/body is untrusted input — use a quoted heredoc (`<<'EOF'`)
  and a shell variable for the title, not double-quote interpolation, which
  would let the shell evaluate `` ` ``/`$(...)`/`${...}` embedded in it.
- Check the composed title/body for sensitive information before running
  this, same as the Phase 5/9 Issue comment checks — the PR is also
  externally visible.
- `--repo "$ISSUE_OWNER/$ISSUE_REPO"` is required (the PR must target the
  repo the Issue lives in, not `gh`'s fork/parent heuristic default). If
  head resolution fails, fall back to `--head <origin-owner>:<branch>`.

## Phase 15: Write Session State

After PR creation, write the PR URL to the session state file so hooks can
reference it directly:

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

If `PR_URL` comes back empty or the `jq` write fails, stop and report it
instead of leaving a stale/empty state file.

## Phase 16: After PR Creation

Run `/pr-health-monitor <PR number>` immediately, without asking first.

`pr-health-monitor` commits/pushes CI fixes, merges in conflicts, edits the
PR body, and can trigger `/handle-pr-reviews` — none of that is "merging,"
so the merge guardrail doesn't apply. No separate confirmation is needed;
the plan was already reviewed via Phase 8's dispatched `plan-reviewer`
sub-agent and posted for the record (Phase 9).

`pr-health-monitor` starts the Copilot review wait as a `Monitor(persistent:
true)` instance in this same session (see `wait-for-copilot-review`'s
SKILL.md) — there is no separate background process or log file to verify.
Report the monitor as running; `/handle-pr-reviews` is called directly in
this conversation when the monitor detects a review.

If requesting or obtaining a Copilot review fails or looks unlikely to ever arrive (e.g. `request-review-copilot` missing, a permissions error, Copilot not enabled on the target repository), do not pause here to ask the user whether to keep waiting or give up. The Copilot review `Monitor` keeps running independently regardless, so move on to Phase 17 unconditionally and immediately.

## Phase 17: Start the PR Close Monitor

Immediately after Phase 16, start the merge/close monitor so cleanup
happens automatically once the PR closes, as long as this session stays
alive:

```bash
PR_NUMBER=$(gh pr view --repo "$ISSUE_OWNER/$ISSUE_REPO" --json number -q .number)
```

Then follow `wait-for-pr-close`'s own SKILL.md (Step 0 already-closed
state check, then `Monitor(..., persistent: true)`), always passing
`--repo "$ISSUE_OWNER/$ISSUE_REPO"` explicitly — this matters even in the
non-fork case, since the PR lives in `ISSUE_OWNER/ISSUE_REPO`, not
necessarily the local `origin` (the fork scenario from Issue #171).

This does not require tmux or a fresh session: when the monitor emits a
`pr_closed` event, call `/pr-cleanup` directly in this same conversation.
If this session ends before the PR is merged or closed, the wait is lost
and the user must run `/pr-cleanup <PR number or URL>` manually later —
this is an accepted limitation (see the design spec behind Issue #200 for
rationale), not a regression from the previous tmux-based design.

The `issue-pr-deep` flow is considered complete once this monitor is running.

## Notes

- Do not drift to other tasks while waiting for review or CI.
- Record the decision log in the spec/plan files or the Issue comment/PR
  body — not extra ad-hoc Markdown files.
- `disable-model-invocation: false` is intentional: this skill needs to
  stay model-invocable so the `issue-pr` dispatcher's own Skill-tool
  hand-off can reach it — `disable-model-invocation: true` would block
  that hand-off too, not just opportunistic auto-trigger on an issue
  number appearing in conversation. The `issue-pr` dispatcher's own
  contract, not this flag, is what keeps this skill from being invoked
  outside that hand-off.
- The plan has no human approval step by design: Phase 8's dispatched `plan-reviewer` sub-agent
  review and Phase 9's Issue-comment posting already surface the plan's content for
  review/record before implementation starts, so an additional explicit `AskUserQuestion`
  gate (the old Phase 10) was removed as redundant. If a plan needs correction after Phase 9,
  treat it the same as any other implementation issue found during Phase 11 (Execute the
  Plan) rather than reopening an approval loop.
