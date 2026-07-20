---
name: issue-pr
description: Use when the user explicitly runs `/issue-pr` to turn a GitHub Issue into a pull request. Dispatches to `issue-pr-deep` (full spec/plan flow) or `issue-pr-lite` (direct implementation) based on Phase 2.5's scale judgment.
argument-hint: "[Issue number or URL]"
disable-model-invocation: true
---

# Create PR from Issue

This skill is a thin dispatcher: it enters a worktree, fetches the Issue,
judges the change's scale, and hands off to either `issue-pr-deep` (full
spec/plan approval flow) or `issue-pr-lite` (direct implementation, no
spec/plan) — see Phase 2.5. It has no Phase 3-onward logic of its own.

Where approval is needed further down this flow (e.g. `issue-pr-deep`'s
spec/plan sign-off), it is done via **AskUserQuestion**, not Claude Code's
native Plan Mode — Plan Mode only allows a single
read-only-until-ExitPlanMode gate, and blocks the Write/Bash/MCP calls this
skill needs starting at Phase 1. This dispatcher's own Phase 2.5 scale
judgment is not one of those approval points — it is made automatically,
without asking the user (see Phase 2.5 below).

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

Before Phase 1, create one task per phase below with the Todo tool
(Phase 1, Phase 2, Phase 2.5), subject = the phase title. This dispatcher's
own flow is short, but it hands off to a much longer delegated flow
(`issue-pr-deep` or `issue-pr-lite`) — track these 3 phases explicitly so
none gets skipped or forgotten mid-run, especially after a context
compaction. Task tracking for the delegated skill's own phases (including
any approval gates and revise-and-repeat loops) is that skill's own
responsibility, not this file's.

Mark each task `in_progress` immediately before starting that phase and
`completed` immediately after finishing it — do not batch updates at the
end.

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
     `git branch --show-current` — the invoked skill's Create Branch phase
     (`issue-pr-deep`'s Phase 10, or `issue-pr-lite`'s Phase 4, depending on
     which one Phase 2.5 selects) needs this exact value to know which
     branch to rename, since the harness's naming convention for that
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
# Resolve via the shared gh-pr-target-repo.sh script's `--origin` mode,
# not via unqualified `gh repo view` — when both `origin` and `upstream`
# remotes exist (this fork scenario itself), `gh repo view` with no
# repository argument resolves ambiguously and can silently return
# `upstream`'s owner/repo instead of `origin`'s, which would make the
# comparison below wrongly conclude there's no fork mismatch and skip the
# rebase entirely. `--origin` always targets `origin` specifically,
# bypassing the script's default upstream-preferring resolution.
ORIGIN_REPO_FULL=$(gh-pr-target-repo.sh --origin)
ORIGIN_OWNER=${ORIGIN_REPO_FULL%%/*}
ORIGIN_REPO=${ORIGIN_REPO_FULL#*/}
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

## Phase 2.5: Scale Judgment

Immediately after Phase 2, judge whether the Issue describes a small-scale
change — do this yourself, reading the Issue body; do not launch an
additional sub-agent for it.

Judge "small-scale" only if **all** of the following hold:

- The change is confined to a single file, or a very small number of
  files.
- No design decision is required (architecture, interface, choosing
  between implementation approaches). Typical small-scale examples: a
  typo fix, a config/version value change, a doc wording fix, a small
  addition that follows an existing pattern.
- The Issue body itself has no ambiguity of interpretation.

When unsure, do **not** judge it small-scale — default to the safe
(`issue-pr-deep`) side.

**Make the call yourself. Do not confirm this judgment with the user via
AskUserQuestion, under any circumstance** — there is no exception for "the
judgment feels uncertain" or "the user might want a say." Briefly state
which path was chosen and why (one or two sentences) before invoking it,
so the decision is visible, but do not turn that statement into a
question.

If you find yourself drafting an AskUserQuestion call with options
resembling "issue-pr-lite で進める" / "issue-pr-deep で進める" (or any
English equivalent, e.g. "Proceed with issue-pr-lite" / "Proceed with
issue-pr-deep"), stop — that is exactly the anti-pattern this rule
forbids, not a legitimate checkpoint.

This judgment is not the kind of "clarifying question" the global
CLAUDE.md's "Use AskUserQuestion for all clarifying questions directed at
the user" rule refers to — that rule governs genuine ambiguity in what
the user wants, not this dispatcher's own internal scale assessment.

Based on the judgment, invoke the chosen skill via the Skill tool
(`issue-pr-deep` or `issue-pr-lite`). The worktree, `ISSUE_OWNER`,
`ISSUE_REPO`, and the Issue body are already in this conversation's
context — the invoked skill starts at its own Phase 3 without redoing
Phase 1/2. Also pass the Issue number/URL extracted in Phase 1 (`$ARGUMENTS`)
explicitly to the invoked skill: unlike this dispatcher, it is not invoked
as a top-level slash command, so `$ARGUMENTS` is not automatically bound
there — `issue-pr-deep`'s Phase 5/9 (Issue comment posting) and
`issue-pr-lite`'s Phase 7 (`Closes #<issue number>`) both rely on it.

This dispatcher has no Phase 3-onward logic of its own; all spec/plan/
implementation/PR-creation responsibility belongs to whichever skill is
invoked here.

## Notes

- Do not drift to other tasks while waiting for review or CI.
- Record the decision log in the superpowers spec/plan files (already
  required by `rules/superpowers.md`) or in the Issue comment / PR body — not
  in extra ad-hoc Markdown files.
- `disable-model-invocation: true` is intentional: this skill hands off to
  a branch-and-PR-creating flow (`issue-pr-deep`/`issue-pr-lite`), which
  requires explicit invocation — not opportunistic auto-trigger on an
  issue number appearing in conversation.
