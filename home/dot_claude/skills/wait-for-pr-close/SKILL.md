---
name: wait-for-pr-close
description: Waits in the background for a pull request to be merged or closed, then triggers /pr-cleanup on detection.
argument-hint: "[PR number] [--repo owner/repo]"
disable-model-invocation: false
---

# Wait for PR Close

Automatically detects when a pull request transitions to `MERGED` or
`CLOSED`, then hands off to `/pr-cleanup` so worktree/branch cleanup happens
even when the user merges or closes the PR outside of this session (where
Claude Code has no way to observe the event directly).

## Usage

```bash
/wait-for-pr-close <PR_NUMBER> [--repo <owner>/<repo>]
```

Or run the script directly:

```bash
${CLAUDE_SKILL_DIR}/scripts/wait-for-pr-close.sh <PR_NUMBER> [--repo <owner>/<repo>] &
```

`--repo` is required whenever the target PR lives in a different repository
than the local `origin` (the fork scenario from Issue #171 — `issue-pr`'s
Phase 19 always passes it explicitly as `$ISSUE_OWNER/$ISSUE_REPO`). If
omitted, the script targets the local `origin`.

## Features

### Detection Logic

- Polls `gh pr view <PR_NUMBER> [--repo <owner>/<repo>] --json state,mergedAt,url`
- **Check interval**: 30 seconds
- **Max wait time**: 30 minutes (60 checks). On timeout, notifies via tmux
  and exits 0 (not an error) — the user can re-run this script later for a
  PR that takes longer to merge.

### Detection Condition

Exits successfully as soon as `state` is `MERGED` or `CLOSED`.

### Background Execution

- **Log file**: `~/.claude/logs/wait-pr-close-<PR_NUMBER>.log`
- **Lock file**: `~/.claude/locks/wait-pr-close-<PR_NUMBER>.lock`
- **Mutual exclusion**: flock prevents multiple concurrent instances for the
  same PR number

### On Detection

1. Notify the user (via Discord notification script)
2. Send `/pr-cleanup <PR_NUMBER_or_URL>` to the current tmux session so
   Claude Code picks up cleanup automatically. When `--repo` was passed and
   differs from the local `origin`, the URL form
   (`https://github.com/<owner>/<repo>/pull/<PR_NUMBER>`) is sent instead of
   the bare number, so `pr-cleanup` targets the correct repository.

## Notes

- Maximum wait time is 30 minutes; re-run manually for a PR that takes
  longer.
- Multiple instances for the same PR number are prevented by flock.
- Check the log file for execution status.

## Troubleshooting

### Check Logs

```bash
tail -f ~/.claude/logs/wait-pr-close-<PR_NUMBER>.log
```

### Remove Lock File (emergency only)

```bash
rm ~/.claude/locks/wait-pr-close-<PR_NUMBER>.lock
```

### Manually Check PR State

```bash
gh pr view <PR_NUMBER> [--repo <owner>/<repo>] --json state,mergedAt,url
```
