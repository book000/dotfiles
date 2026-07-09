---
name: issue-pr-deep
description: Full spec/plan approval flow for turning a GitHub Issue into a pull request. Invoked by the `issue-pr` dispatcher for non-trivial changes.
disable-model-invocation: true
---

# issue-pr-deep: full spec/plan approval flow

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

If a revise loop (Phase 6 or Phase 10) sends execution back to an earlier
phase, create a **new** task for the repeated phase (e.g. "Phase 3: Write
the Spec (revision 2)") rather than reopening the completed one.

## Phase 3: Write the Spec

Invoke **superpowers:brainstorming** with the issue content as the starting
problem, relaying any clarifying questions via AskUserQuestion. It produces
a spec file under `docs/superpowers/specs/`.

Explicitly instruct it, every time, to write the spec document's body in the
language required by the target project's CLAUDE.md (for this repository,
Japanese — `会話は日本語で行う`); code blocks/commands/identifiers may stay
as-is. Do not assume this is inferred from context.

Do not ask a content-free "may I proceed" confirmation before this phase.
Genuine requirement-clarifying questions (real ambiguity in the Issue's
request) are fine via AskUserQuestion; asking permission with no new
information is not.

Skip brainstorming's own "commit the spec to git" step: per
`rules/superpowers.md`'s "Local-Only Artifacts" policy, `docs/superpowers/`
is `.gitignore`d and stays a local untracked artifact.

## Phase 4: Review the Spec

`rules/superpowers.md` requires a sub-agent review of every spec file; it
fires automatically after Phase 3. Wait for it and confirm the reported
fixes/ambiguities look correct before moving on.

If it doesn't fire, do not do it yourself — stop and tell the user it
didn't run, and ask how to proceed.

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

Invoke **superpowers:writing-plans** against the approved spec to produce a
plan file under `docs/superpowers/plans/`.

Same language instruction as Phase 3 (Japanese for this repository, code/
commands/identifiers as-is), and same "skip the commit-to-git step" rule —
the plan stays a local untracked artifact.

## Phase 8: Review the Plan

Same as Phase 4, for the plan file: wait for the automatic sub-agent review
and confirm the result. If it doesn't fire, same rule — stop and ask.

## Phase 9: Post the Plan as an Issue Comment

Same as Phase 5, for the plan file — follow `rules/issue-comment-docs.md`
directly:

```bash
url=$(gh issue comment "$ARGUMENTS" --repo "$ISSUE_OWNER/$ISSUE_REPO" --body-file <plan-file-path>)
PLAN_COMMENT_URL="$url"
PLAN_COMMENT_ID=${url##*issuecomment-}
```

This must be a **new** comment, never reusing `SPEC_COMMENT_ID`.

Same revision rule as Phase 5: if repeating after Phase 10, update the
existing plan comment by its own ID:

```bash
gh api "repos/$ISSUE_OWNER/$ISSUE_REPO/issues/comments/$PLAN_COMMENT_ID" -X PATCH -F body=@<plan-file-path>
```

Same fallback as Phase 5 if the post fails.

## Phase 10: Approve the Plan

Use **AskUserQuestion** again for explicit plan approval — Phase 6's spec
approval does not carry over, since a plan can diverge from its spec.

Same requirements as Phase 6: the question text MUST include `PLAN_COMMENT_URL`
(Phase 9), and the same two fixed options apply (see Phase 6).

If revise is chosen, get what to change via "Other", update the plan, and
repeat Phases 7–10 (Phase 9 becomes an update via `PLAN_COMMENT_ID`).

## Phase 11: Create Branch

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

## Phase 12: Execute the Plan

Invoke **superpowers:executing-plans** (or
**superpowers:subagent-driven-development** for independent tasks) against
the approved plan. Run its tasks without re-confirming each one with the
user; only stop for genuine blockers the plan didn't anticipate (missing
credentials, contradictory requirements).

If a task fails (test failure, compile error, a sub-agent reporting it
couldn't complete), stop and report it before moving to Phase 13 — do not
treat it as done.

## Phase 13: Verify

Invoke **superpowers:verification-before-completion** before creating the PR.
If it reports a failure, go back to Phase 12 to fix it — do not proceed to
Phase 14 with a known-failing verification.

## Phase 14: Deep Review

Run `/deep-review` (no arguments — local diff mode) per `rules/workflow.md`
ADR-003. Fix every finding scored ≥ 50 before Phase 15 — this is a required
gate the Stop/PostToolUse hooks enforce.

## Phase 15: Create PR

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

## Phase 16: Write Session State

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

## Phase 17: After PR Creation

Run `/pr-health-monitor <PR number>` immediately, without asking first.

`pr-health-monitor` commits/pushes CI fixes, merges in conflicts, edits the
PR body, and can trigger `/handle-pr-reviews` — none of that is "merging,"
so the merge guardrail doesn't apply. No separate confirmation is needed;
Phase 10 already approved the plan.

`pr-health-monitor` starts the Copilot review wait as a `Monitor(persistent:
true)` instance in this same session (see `wait-for-copilot-review`'s
SKILL.md) — there is no separate background process or log file to verify.
Report the monitor as running; `/handle-pr-reviews` is called directly in
this conversation when the monitor detects a review.

## Phase 18: Start the PR Close Monitor

Immediately after Phase 17, start the merge/close monitor so cleanup
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
- `disable-model-invocation: true` is intentional: only the `issue-pr`
  dispatcher's explicit hand-off reaches this skill, not opportunistic
  auto-trigger on an issue number appearing in conversation.
