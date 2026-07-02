---
name: pr-cleanup
description: Cleans up after a pull request is merged or closed — removes the worktree/branch, updates the local default branch, and syncs a fork if applicable. Triggered automatically by wait-for-pr-close, or run manually with /pr-cleanup <PR number or URL>.
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
if echo "$PR_ARG" | grep -q 'github\.com'; then
  OWNER=$(echo "$PR_ARG" | sed -E 's#.*github\.com/([^/]+)/.*#\1#')
  REPO=$(echo "$PR_ARG" | sed -E 's#.*github\.com/[^/]+/([^/]+)/pull/.*#\1#')
  PR_NUMBER=$(echo "$PR_ARG" | sed -E 's#.*/pull/([0-9]+).*#\1#')
else
  OWNER=$(gh repo view --json owner --jq '.owner.login')
  REPO=$(gh repo view --json name --jq '.name')
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

## Step 1.5: Archive Confluence Spec/Plan Pages

Run this whenever Step 1 passed (`state` is `MERGED` or `CLOSED`) —
regardless of which of the two, since abandoned (closed-without-merge)
spec/plan work should also be tidied up. This step must never block Step 2
onward: any failure here is a warning, not a stop condition.

1. Fetch the PR body:

   ```bash
   if ! PR_BODY=$(gh pr view "$PR_NUMBER" --repo "$OWNER/$REPO" --json body -q .body); then
     echo "Warning: failed to fetch PR body for Confluence archiving; skipping Step 1.5" >&2
     PR_BODY=""
   fi
   ```

   A `gh pr view` failure (auth, network, transient API error) is not the
   same thing as "this PR has no spec/plan documents" — treat a non-zero
   exit code as its own warning (per item 6 below) rather than silently
   falling through to the empty-`$CONFLUENCE_URLS` case in item 2.

2. Extract Confluence URLs from `Spec:` / `Plan:` lines:

   ```bash
   # sed -n returns exit status 0 even with no match, so this won't abort
   # under set -e when there's no Spec/Plan line (grep would exit 1 on no match)
   CONFLUENCE_URLS=$(printf '%s\n' "$PR_BODY" | sed -nE 's/^(Spec|Plan): (https?:\/\/.*)/\2/p')
   ```

   If `$CONFLUENCE_URLS` is empty (and step 1 did not already fail), skip
   the rest of this step entirely — not every PR carries spec/plan
   documents.

3. Before resolving any URL, validate its hostname matches the Confluence
   site already confirmed via `rules/confluence.md`'s cloudId resolution
   (the same site the spec/plan pages were uploaded to in Phase 5/9 of
   `issue-pr`). A PR body is external input — including on PRs from
   contributors other than this session — so do not resolve or act on a
   `Spec:`/`Plan:` URL pointing at an unexpected host; treat a mismatch as
   a warning (item 6) and skip that URL.

4. For each remaining URL, resolve the Confluence page (via
   `mcp__atlassian__getConfluencePage`, passing the full URL as-is) and
   note its `spaceId`. Whether the tool resolves a full Confluence URL
   directly is unverified — if resolution fails, this is covered by the
   warning-and-continue rule in item 6 below.

5. Within each distinct `spaceId` seen across the URLs (typically one,
   since Spec and Plan usually share a space — search once per space and
   reuse the result, not once per URL), search for an existing archive
   parent page:

   ```
   mcp__atlassian__searchConfluenceUsingCql with
   cql: title = "Archived Specs & Plans" AND space.id = "<spaceId>" AND type = page
   ```

   (`space.id` is used directly since step 4 already yields `spaceId`, not
   a space key — no separate key lookup is needed.)

   - If found, use its page ID as the archive parent.
   - If not found, create it with `mcp__atlassian__createConfluencePage`
     (`title: "Archived Specs & Plans"`, same `parentId` as the original
     spec/plan page if it has one, otherwise no `parentId`).

6. For each spec/plan page, call `mcp__atlassian__updateConfluencePage`
   with `parentId` set to the archive parent's page ID from step 5 (the one
   matching that page's `spaceId`). Do not change the title or body.

7. If any page's lookup or move fails (network error, permission error,
   URL didn't parse to a resolvable page, or the host-mismatch case in item
   3), log it as a warning and continue — do not stop Step 2 (worktree/
   branch removal) because of a Confluence side-effect failure. Include
   this step's warnings (if any) in Step 5's completion report so a
   persistently failing archive step is not silently invisible to the user.

## Step 2: Remove the Worktree or Branch

`ExitWorktree` only operates on a worktree created by `EnterWorktree` **in
the current session**, and is a no-op otherwise. Because `pr-cleanup` is
mainly triggered from a fresh session (a new tmux prompt spawned by
`wait-for-pr-close`, or a manual run days later), check whether the current
session actually owns a matching worktree before deciding which removal
path to use:

```bash
HEAD_REF=$(gh pr view "$PR_NUMBER" --repo "$OWNER/$REPO" --json headRefName -q .headRefName)
```

- **If this session's `EnterWorktree` created the worktree for `HEAD_REF`**
  (i.e. you got here via Phase 19 of `issue-pr` continuing in the same
  session, without a session break): call
  `ExitWorktree(action: "remove", discard_changes: true)`. Passing
  `discard_changes: true` without re-confirming with the user is safe and
  required here — Step 1 already confirmed the PR is `MERGED`/`CLOSED`, so
  the branch's content is either already incorporated upstream or
  explicitly abandoned. This also covers the squash-merge case, where the
  local branch looks like it has "uncommitted" changes relative to the
  squashed commit even though nothing is actually lost.

- **Otherwise (the common case — a fresh session, e.g. triggered by
  `wait-for-pr-close`'s tmux notification, or a manual run in a new
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
DEFAULT_BRANCH=$(gh repo view --json defaultBranchRef -q .defaultBranchRef.name)
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
if gh repo view --json parent -q .parent 2>/dev/null | grep -qv '^null$'; then
  gh repo sync
fi
```

`gh repo view --json parent` returns `null` for non-fork repositories;
`gh repo sync` is only run when a parent exists (i.e. `origin` is a fork).

## Step 5: Report Completion

Report to the user that cleanup completed (worktree/branch removed, default
branch updated, fork synced if applicable). If Step 1.5 logged any warnings
(Confluence page lookup/move failures, host mismatches), include them here
too — Step 1.5 is warning-only and never blocks cleanup, but that also means
this is the only place its failures reach the user; do not let them go
unreported. Do not send a duplicate Discord notification here —
`wait-for-pr-close` already sent one on detection when this skill was
triggered automatically.
