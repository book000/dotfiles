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
review, or Issue-comment posting — those stay in superpowers /
`rules/issue-comment-docs.md`.

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

Before Phase 1, create one task per phase below with the Todo tool,
subject = the phase title. This is a long, multi-phase flow spanning two
approval gates and several delegated skills — track it explicitly so no
phase gets skipped or forgotten mid-run, especially after a revise-and-repeat
loop (Phase 6 or Phase 10) or a context compaction.

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
     `git branch --show-current` — Phase 11 needs this exact value to know
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
gh issue view "$ARGUMENTS" --json title,state,body,comments,author,url
```

If this command fails (auth, network, issue doesn't exist) or the issue is
not OPEN, stop here and report it to the user — do not guess at intent and
continue. Turning a closed or nonexistent issue into a PR is not a warning-
level situation, it's a reason to stop.

Extract `ISSUE_OWNER` and `ISSUE_REPO` from the returned `url` field
(`https://github.com/<owner>/<repo>/issues/<number>`):

```bash
# grep -oP（PCRE）は macOS の BSD grep では動かないため sed -E で移植可能な形にする
ISSUE_URL=$(gh issue view "$ARGUMENTS" --json url -q .url)
ISSUE_OWNER=$(echo "$ISSUE_URL" | sed -E 's#.*github\.com/([^/]+)/.*#\1#')
ISSUE_REPO=$(echo "$ISSUE_URL" | sed -E 's#.*github\.com/[^/]+/([^/]+)/issues/.*#\1#')
if [ -z "$ISSUE_OWNER" ] || [ -z "$ISSUE_REPO" ]; then
  echo "ERROR: failed to extract owner/repo from Issue URL: $ISSUE_URL" >&2
  exit 1
fi
```

If extraction fails, stop and report it to the user — every later phase
that targets a specific repository (`gh issue comment`, `gh pr create`,
`gh pr view` from the new `wait-for-pr-close` phase) depends on
`ISSUE_OWNER`/`ISSUE_REPO` being correct. **`ISSUE_OWNER`/`ISSUE_REPO` is
the repository the Issue actually lives in — this is what determines the PR
destination in every later phase, regardless of whether the local checkout
is a fork.**

### Rebase onto the correct base branch (fork scenario)

`EnterWorktree` in Phase 1 created the working branch off
`origin/<default-branch>`. If `ISSUE_OWNER/ISSUE_REPO` differs from the
local `origin`'s owner/repo (a fork working on an upstream Issue), `origin`'s
default branch may be stale relative to `ISSUE_OWNER/ISSUE_REPO`'s. Rebase
onto the correct base immediately, before any spec/plan/implementation work
begins:

```bash
ORIGIN_OWNER=$(gh repo view --json owner -q .owner.login)
ORIGIN_REPO=$(gh repo view --json name -q .name)
if [ "$ISSUE_OWNER/$ISSUE_REPO" != "$ORIGIN_OWNER/$ORIGIN_REPO" ]; then
  # Reuse an existing remote pointing at ISSUE_OWNER/ISSUE_REPO, or add one.
  REMOTE_NAME=$(git remote -v | grep -F "github.com/$ISSUE_OWNER/$ISSUE_REPO" | head -1 | cut -f1)
  if [ -z "$REMOTE_NAME" ]; then
    REMOTE_NAME="upstream"
    if git remote get-url "$REMOTE_NAME" >/dev/null 2>&1; then
      echo "ERROR: remote '$REMOTE_NAME' already exists but does not point at $ISSUE_OWNER/$ISSUE_REPO" >&2
      exit 1
    fi
    git remote add "$REMOTE_NAME" "https://github.com/$ISSUE_OWNER/$ISSUE_REPO.git"
  fi
  DEFAULT_BRANCH=$(gh repo view "$ISSUE_OWNER/$ISSUE_REPO" --json defaultBranchRef -q .defaultBranchRef.name)
  git fetch "$REMOTE_NAME" "$DEFAULT_BRANCH"
  git reset --hard "$REMOTE_NAME/$DEFAULT_BRANCH"
fi
```

This is safe because no implementation work has happened yet at this point
in the flow — `git reset --hard` here discards nothing of value. If the
`git remote add` step fails because a same-named remote already exists
pointing elsewhere, stop and ask the user how to proceed rather than
overwriting it.

## Phase 3: Write the Spec

Invoke **superpowers:brainstorming** with the issue content as the starting
problem. Relay any clarifying questions it raises to the user via
AskUserQuestion. It produces a spec file under `docs/superpowers/specs/`.

When invoking it, explicitly instruct it to write the spec document's body
in the language required by the target project's CLAUDE.md (for this
repository, Japanese — `会話は日本語で行う`). Code blocks, commands, and
identifiers may stay in their original form. This must be stated explicitly
in the prompt every time — do not assume the sub-skill infers it from
context, since roughly one run in five otherwise defaults to English.

Do not ask a content-free "may I proceed" confirmation between Phase 2 and
this phase (e.g. "spec を作成してよいですか？"). Genuine requirement-
clarifying questions (where the Issue's request could be interpreted two or
more ways) are fine and expected via AskUserQuestion — the distinction is
whether the question surfaces a real ambiguity to resolve, versus asking
permission to do the next scheduled step with no new information attached.

superpowers's brainstorming skill includes a step that commits the spec
document to git. Skip that step here: per `rules/superpowers.md`'s
"Local-Only Artifacts" policy, `docs/superpowers/` is `.gitignore`d and the
spec file stays as a local untracked artifact — do not force-add it.

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

## Phase 5: Post the Spec as an Issue Comment

`rules/issue-comment-docs.md` covers this case (the spec is tied to this
Issue) — follow its procedure directly:

```bash
url=$(gh issue comment "$ARGUMENTS" --repo "$ISSUE_OWNER/$ISSUE_REPO" --body-file <spec-file-path>)
SPEC_COMMENT_URL="$url"
SPEC_COMMENT_ID=${url##*issuecomment-}
```

Capture `SPEC_COMMENT_URL`/`SPEC_COMMENT_ID` — you need the URL for Phase 6
and the ID for any later revision.

If this is a revision (you're back here after Phase 6 sent you to repeat
Phases 3–6), update the existing comment by its ID instead of creating a new
one:

```bash
gh api "repos/$ISSUE_OWNER/$ISSUE_REPO/issues/comments/$SPEC_COMMENT_ID" -X PATCH -F body=@<spec-file-path>
```

Do not use `--edit-last` — it targets "the last comment posted by the
current user" on the whole Issue, and would silently overwrite the plan's
comment (Phase 9) if the plan was already posted before a spec revision.

If `gh issue comment` / `gh api` fails (auth, network, permission), follow
`rules/issue-comment-docs.md`'s own fallback: report the error to the user
and ask how to proceed.

## Phase 6: Approve the Spec

Use **AskUserQuestion** to get explicit spec approval before moving on to
Phase 7. No exceptions — not for "the spec is obviously fine" and not for
"ask forgiveness after Phase 7 instead."

The question text MUST include the Issue comment URL (`SPEC_COMMENT_URL`)
captured in Phase 5. If Phase 5's post failed and fell back per
`rules/issue-comment-docs.md`, you must have already reported that to the
user before reaching this phase — do not silently ask for approval without
ever having surfaced the failure.

Fix the options to exactly these two (plus AskUserQuestion's built-in
"Other" free-text, which covers ad-hoc revision requests — e.g. the user
typing what to change directly). Note: AskUserQuestion's `options` array
requires at least 2 entries — passing only 1 fails with `Too small:
expected array to have >=2 items`, so always pass both of the following,
never just one:

- "承認する" (Approve)
- "修正してほしい(Otherで内容を指示)" (Revise — specify what via Other)

If the second option is chosen, ask the user via the "Other" free-text field
what to revise (there is no page-comment mechanism on a GitHub Issue
comment the way there was on a Confluence page), incorporate the requested
changes into the spec, and repeat Phases 3–6 (Phase 5 becomes an Issue
comment update via `SPEC_COMMENT_ID`, not a new comment).

## Phase 7: Write the Plan

Invoke **superpowers:writing-plans** against the approved spec to produce a
plan file under `docs/superpowers/plans/`.

Same language instruction as Phase 3: explicitly tell it to write the plan
document's body in the language required by the target project's CLAUDE.md
(Japanese for this repository), with code blocks/commands/identifiers left
in their original form.

Same as Phase 3: skip writing-plans' "commit the plan document to git" step
— the plan file stays as a local untracked artifact per
`rules/superpowers.md`'s "Local-Only Artifacts" policy.

## Phase 8: Review the Plan

Same as Phase 4, for the plan file: `rules/superpowers.md`'s sub-agent review
fires automatically. Wait for it and confirm the result before moving on. If
it doesn't fire, same rule as Phase 4 — stop and ask the user, don't do the
review yourself.

## Phase 9: Post the Plan as an Issue Comment

Same as Phase 5, for the plan file — follow `rules/issue-comment-docs.md`
directly:

```bash
url=$(gh issue comment "$ARGUMENTS" --repo "$ISSUE_OWNER/$ISSUE_REPO" --body-file <plan-file-path>)
PLAN_COMMENT_URL="$url"
PLAN_COMMENT_ID=${url##*issuecomment-}
```

This must be a **new** comment, separate from `SPEC_COMMENT_ID` — never
reuse or overwrite the spec's comment.

Same revision rule as Phase 5: if this is a repeat after Phase 10 sent you
back, update the existing plan comment by its own ID instead of creating a
new one:

```bash
gh api "repos/$ISSUE_OWNER/$ISSUE_REPO/issues/comments/$PLAN_COMMENT_ID" -X PATCH -F body=@<plan-file-path>
```

Same fallback as Phase 5 if the post fails.

## Phase 10: Approve the Plan

Use **AskUserQuestion** again for explicit plan approval before moving on to
Phase 11 — the spec's approval in Phase 6 does not carry over, since a plan
can diverge from its spec. "The spec was already approved so the plan is
implied" is exactly the shortcut this gate blocks.

Same requirements as Phase 6: the question text MUST include the Issue
comment URL (`PLAN_COMMENT_URL`) captured in Phase 9 (report any post
failure to the user before this phase, per `rules/issue-comment-docs.md`'s
fallback), and the options are fixed to exactly (both entries required —
AskUserQuestion rejects a single-entry `options` array):

- "承認する" (Approve)
- "修正してほしい(Otherで内容を指示)" (Revise — specify what via Other)

If the second option is chosen, ask the user via "Other" what to revise,
incorporate the requested changes into the plan, and repeat Phases 7–10
(Phase 9 becomes an Issue comment update via `PLAN_COMMENT_ID`, not a new
comment).

## Phase 11: Create Branch

`EnterWorktree` (Phase 1) already created a branch off
`origin/<default-branch>` — this phase renames that branch to a Conventional
Branch name instead of creating a new one.

```bash
git status --porcelain   # should be empty right after EnterWorktree; if not, stop and ask the user
git branch -m <worktree_branch_name> <branch_name>
```

Derive `<branch_name>` from the Issue number/title following Conventional
Branch (feat/fix/docs/refactor), e.g. `fix/123-short-description`. Slugify
the derived portion to `[a-z0-9-]` before substituting it into the command —
the issue title is untrusted input, and an unsanitized title containing
shell metacharacters (`` ` ``, `$(...)`, `${...}`) would be evaluated by the
shell if pasted in verbatim.

`<worktree_branch_name>` is the exact value Phase 1 recorded via
`git branch --show-current` right after `EnterWorktree` succeeded. Use the
explicit two-argument form of `git branch -m` (rename `<worktree_branch_name>`
to `<branch_name>`) rather than the one-argument form that renames whatever
branch is currently checked out — the one-argument form would silently rename
the wrong branch if the checked-out branch changed between Phase 1 and
Phase 11. Before running the command, compare `<worktree_branch_name>` against
the current `git branch --show-current` output; if they don't match (e.g. the
user manually switched branches between Phase 1 and Phase 11), stop and ask
the user how to proceed instead of overwriting whatever they were doing.

If `git branch -m <branch_name>` fails because `<branch_name>` already exists
(e.g. a retry after an earlier failed run), do not force-rename over it — that
would silently merge two unrelated branches' history under one name. Stop
and ask the user whether to reuse, delete, or rename.

## Phase 12: Execute the Plan

Invoke **superpowers:executing-plans** (or
**superpowers:subagent-driven-development** for independent tasks) against
the approved plan file. The plan was already approved in Phase 10 — run its
tasks without re-confirming each one with the user. Only stop for genuine
blockers the plan didn't anticipate (missing credentials, contradictory
requirements).

If a task fails (test failure, compile error, a sub-agent reporting it
couldn't complete its task), that is not a blocker to route around — stop and
report it to the user before moving on to Phase 13. Do not treat a failed
task as done because the plan didn't explicitly anticipate the failure.

## Phase 13: Verify

Invoke **superpowers:verification-before-completion** before creating the PR.
If it reports a failure, go back to Phase 12 to fix it — do not proceed to
Phase 14 with a known-failing verification.

## Phase 14: Deep Review

Run `/deep-review` (no arguments — local diff mode) per `rules/workflow.md`
ADR-003 and this project's Pre-PR checklist. Fix every finding scored ≥ 50
before moving on to Phase 15. This is a required gate, not an optional
extra step — skipping it is what the Stop/PostToolUse hooks exist to catch.

## Phase 15: Create PR

`gh pr create` requires the branch to already exist on a remote — it does
not push for you. Push the branch first, or `gh pr create` fails with
`aborted: you must first push the current branch to a remote, or use the
--head flag`:

```bash
git push -u origin "$(git branch --show-current)"
```

(In the fork scenario, `origin` here is the local checkout's own remote —
the one the branch actually lives on — not `$ISSUE_OWNER/$ISSUE_REPO`.)

Set `PR_TITLE` explicitly before calling `gh pr create` — derive it from the
issue title / spec summary, e.g.:

```bash
PR_TITLE="<derived from the issue title / spec summary>"
gh pr create --repo "$ISSUE_OWNER/$ISSUE_REPO" --title "$PR_TITLE" --body "$(cat <<'EOF'
<PR body>
EOF
)"
```

- `<PR body>`: summarize from the approved spec and plan; include
  `Closes #<issue number>` so the issue auto-closes on merge. Also include
  the Spec/Plan Issue comment URLs captured in Phase 5 (`SPEC_COMMENT_URL`)
  and Phase 9 (`PLAN_COMMENT_URL`), in this exact format:

  ```
  Spec: [Issue comment URL]
  Plan: [Issue comment URL]
  ```

- Language: follow the project CLAUDE.md if specified, otherwise Japanese.
  Current state only, no update history.
- The issue title/body feeding `<title>`/`<PR body>` is untrusted input —
  use a quoted heredoc (`<<'EOF'`, as above) and a shell variable for the
  title, not raw double-quote interpolation. Double quotes let the shell
  evaluate any `` ` `` / `$(...)` / `${...}` embedded in issue-derived text
  before `gh` ever sees it.
- Before running this command, check the composed title/body for sensitive
  information (tokens, internal URLs, credentials) the same way the
  spec/plan Issue comments are checked before posting (Phase 5/9) — the PR
  is also externally visible.
- `--repo "$ISSUE_OWNER/$ISSUE_REPO"` is required: the PR must be created
  against the repository the Issue actually lives in (set in Phase 2), not
  wherever `gh`'s own fork/parent heuristic would default to. The head side
  (the fork's branch) is resolved automatically by `gh`; if that resolution
  fails, fall back to explicitly passing
  `--head <origin-owner>:<branch>`.

## Phase 16: Write Session State

After PR creation, write the PR URL to the session state file so hooks can reference it
without parsing the transcript:

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
instead of leaving a stale/empty state file — hooks read this file without
parsing the transcript, so a silently broken write here breaks them too.

## Phase 17: After PR Creation

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

If `pr-health-monitor` (or `issue-pr` itself, in a fork scenario) launches
`wait-for-copilot-review` in the background, verify the launch actually
succeeded before reporting completion — do not unconditionally state
"Copilot レビューが届き次第自動的にトリガーされます". Check for the
expected log file (`~/.claude/logs/wait-copilot-review-<PR 番号>.log`) and that the
process is still running (`ps aux | grep wait-for-copilot-review`). If
either check fails, report that the background monitor failed to start and
that manual re-invocation may be needed, instead of promising automation
that didn't actually start.

## Phase 18: Launch Background Monitoring

Immediately after Phase 17, launch the merge/close monitor in the
background so cleanup happens even if the user merges or closes the PR
outside this session:

```bash
PR_NUMBER=$(gh pr view --repo "$ISSUE_OWNER/$ISSUE_REPO" --json number -q .number)
~/.claude/skills/wait-for-pr-close/scripts/wait-for-pr-close.sh "$PR_NUMBER" --repo "$ISSUE_OWNER/$ISSUE_REPO" &
```

Always pass `--repo "$ISSUE_OWNER/$ISSUE_REPO"` explicitly here, even in the
non-fork case — omitting it makes `wait-for-pr-close.sh` fall back to the
local `origin`, which is wrong whenever the fork scenario from Issue #171
applies (the PR lives in `ISSUE_OWNER/ISSUE_REPO`, not `origin`).

This is a fire-and-forget background launch, matching how
`wait-for-copilot-review` is used elsewhere — the `issue-pr` flow is
considered complete once this is launched. Detection and cleanup
(`/pr-cleanup`) happen outside this session, in a fresh tmux prompt, once
the monitor detects the PR closing.

## Notes

- Do not drift to other tasks while waiting for review or CI.
- Record the decision log in the superpowers spec/plan files (already
  required by `rules/superpowers.md`) or in the Issue comment / PR body — not
  in extra ad-hoc Markdown files.
- `disable-model-invocation: true` is intentional: this skill ends in a
  branch and a PR, which requires explicit invocation — not opportunistic
  auto-trigger on an issue number appearing in conversation.
