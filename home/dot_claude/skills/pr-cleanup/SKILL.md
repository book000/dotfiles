---
name: pr-cleanup
description: Cleans up after a pull request is merged or closed — removes the worktree/branch, updates the local default branch, and syncs a fork if applicable. Called directly by wait-for-pr-close on detection, or run manually with /pr-cleanup <PR number or URL>.
argument-hint: "[PR number or URL]"
disable-model-invocation: false
---

# PR Cleanup

Cleans up local state after a pull request has been merged or closed —
including the case where the user merged/closed it outside this session
(manually, or via another tool), which Claude Code has no way to observe
directly. This is a generic cleanup skill, not specific to `issue-pr`: it
can be invoked manually for any PR, or automatically by `wait-for-pr-close`.

## Usage

```
/pr-cleanup <PR number or URL>
```

**Examples:**
- `/pr-cleanup 123`
- `/pr-cleanup https://github.com/owner/repo/pull/123`

## Step 0: Resolve PR Info

```bash
# grep -oP (PCRE) doesn't work on macOS's BSD grep, so use sed -E for a portable form
PR_ARG="$ARGUMENTS"

# Always resolve the local `origin` remote's owner/repo directly from its
# URL, not via unqualified `gh repo view`. When both `origin` and `upstream`
# remotes exist (the fork scenario), `gh repo view` with no repository
# argument resolves ambiguously and can silently return `upstream`'s
# owner/repo instead of `origin`'s — this previously broke the Step 4 fork
# check (it read `upstream`'s own `parent`, which is `null`, and concluded
# `origin` wasn't a fork when it actually was).
ORIGIN_URL=$(git remote get-url origin)
ORIGIN_OWNER=$(echo "$ORIGIN_URL" | sed -E 's#^(git@[^:]+:|https://[^/]+/)##; s#\.git$##' | cut -d/ -f1)
ORIGIN_REPO=$(echo "$ORIGIN_URL" | sed -E 's#^(git@[^:]+:|https://[^/]+/)##; s#\.git$##' | cut -d/ -f2)

if echo "$PR_ARG" | grep -q 'github\.com'; then
  OWNER=$(echo "$PR_ARG" | sed -E 's#.*github\.com/([^/]+)/.*#\1#')
  REPO=$(echo "$PR_ARG" | sed -E 's#.*github\.com/[^/]+/([^/]+)/pull/.*#\1#')
  PR_NUMBER=$(echo "$PR_ARG" | sed -E 's#.*/pull/([0-9]+).*#\1#')
else
  OWNER="$ORIGIN_OWNER"
  REPO="$ORIGIN_REPO"
  PR_NUMBER="$PR_ARG"
fi
```

## Step 1: Confirm the PR Is Actually Closed

```bash
gh pr view "$PR_NUMBER" --repo "$OWNER/$REPO" --json state,headRefName,baseRefName,url,headRepositoryOwner
```

If `state` is not `MERGED` or `CLOSED`, stop here and report it to the
user — do not delete a branch backing a still-open PR just because this
skill was invoked manually or by mistake.

## Step 2: Remove the Worktree or Branch

`ExitWorktree` only operates on a worktree created by `EnterWorktree` **in
the current session**, and is a no-op otherwise. `pr-cleanup` is called
either directly in the same conversation as `wait-for-pr-close` (its
`Monitor` detected the PR closing while this session was still alive) or in
a genuinely fresh session (a manual run days later, or after the original
session ended before detection). Check whether the current session actually
owns a matching worktree before deciding which removal path to use:

```bash
HEAD_REF=$(gh pr view "$PR_NUMBER" --repo "$OWNER/$REPO" --json headRefName -q .headRefName)
```

- **If this session's `EnterWorktree` created the worktree for `HEAD_REF`**
  (i.e. you got here via Phase 18 of `issue-pr` continuing in the same
  session, without a session break): call
  `ExitWorktree(action: "remove", discard_changes: true)`. Passing
  `discard_changes: true` without re-confirming with the user is safe and
  required here — Step 1 already confirmed the PR is `MERGED`/`CLOSED`, so
  the branch's content is either already incorporated upstream or
  explicitly abandoned. This also covers the squash-merge case, where the
  local branch looks like it has "uncommitted" changes relative to the
  squashed commit even though nothing is actually lost.

- **Otherwise (a fresh session — e.g. this session's `wait-for-pr-close`
  monitor never fired before it ended, or this is a manual run in a new
  session)**: `ExitWorktree` cannot see a worktree it did not create, so
  fall back to raw `git worktree` commands:

  ```bash
  WORKTREE_PATH=$(git worktree list --porcelain | awk -v ref="refs/heads/$HEAD_REF" '
    /^worktree /{path=$2} /^branch /{if ($2==ref) print path}')
  if [ -n "$WORKTREE_PATH" ]; then
    git worktree remove --force "$WORKTREE_PATH"
  fi
  ```

  `--force` is required for the same reason `discard_changes: true` is
  required in the `ExitWorktree` branch above — Step 1 already confirmed
  the PR is `MERGED`/`CLOSED`, so any apparent uncommitted state (e.g. from
  a squash merge) is safe to discard without asking the user again.

If it's a plain branch (no worktree involved either way):

```bash
git branch -D "$HEAD_REF"
```

## Step 3: Update the Local Default Branch

```bash
DEFAULT_BRANCH=$(gh repo view "$ORIGIN_OWNER/$ORIGIN_REPO" --json defaultBranchRef -q .defaultBranchRef.name)
git checkout "$DEFAULT_BRANCH"
git pull
```

If `DEFAULT_BRANCH` comes back empty, or either command exits non-zero
(e.g. uncommitted local changes blocking the checkout, a network failure on
pull), stop here and report it to the user — do not continue to Step 4/5 and
report cleanup as complete when the local checkout may still be out of sync.

This always targets the local `origin`'s default branch — even when the PR
itself was created against a different repository (the fork/upstream
scenario from Issue #171), the worktree/branch being cleaned up lives in
the local checkout, which is always `origin`.

## Step 4: Sync the Fork (if applicable)

```bash
if gh repo view "$ORIGIN_OWNER/$ORIGIN_REPO" --json parent -q .parent 2>/dev/null | grep -qv '^null$'; then
  gh repo sync "$ORIGIN_OWNER/$ORIGIN_REPO"
fi
```

`gh repo view "$ORIGIN_OWNER/$ORIGIN_REPO" --json parent` returns `null` for
non-fork repositories; `gh repo sync` is only run when a parent exists
(i.e. `origin` is a fork). Both calls explicitly target `$ORIGIN_OWNER/$ORIGIN_REPO`
(resolved in Step 0) rather than relying on `gh`'s ambiguous no-argument
resolution — see the comment in Step 0 for why.

## Step 5: Report Completion

Report to the user that cleanup completed (worktree/branch removed, default
branch updated, fork synced if applicable). Do not send a duplicate Discord
notification here — `wait-for-pr-close` already sent one on detection when
this skill was triggered automatically.
