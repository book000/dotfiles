---
name: wait-for-pr-close
description: Waits for a pull request to be merged or closed using the Monitor tool, then triggers /pr-cleanup on detection — no tmux required.
argument-hint: "[PR number] [--repo owner/repo]"
disable-model-invocation: false
---

# Wait for PR Close

Detects when a pull request transitions to `MERGED` or `CLOSED`, using the
`Monitor` tool for in-session polling, then hands off to `/pr-cleanup`.
This only works while the current session stays alive — see Notes.

## Usage

```
/wait-for-pr-close <PR number> [--repo owner/repo]
```

Resolve `OWNER`, `REPO`, `PR_NUMBER` from the caller's context. Pass the
repository explicitly whenever the target PR lives in a different
repository than the local `origin` (the fork scenario from Issue #171 —
`issue-pr`'s Phase 18 always resolves this as `$ISSUE_OWNER/$ISSUE_REPO`).

Validate the resolved values before using them below — they end up
embedded directly in a script that `Monitor` executes, so an unvalidated
value here is a shell-injection risk, not just a correctness one:

```bash
if ! [[ "$PR_NUMBER" =~ ^[0-9]+$ ]]; then
  echo "ERROR: PR_NUMBER must be numeric, got: $PR_NUMBER" >&2
  exit 1
fi
if ! [[ "$OWNER" =~ ^[A-Za-z0-9_.-]+$ ]] || ! [[ "$REPO" =~ ^[A-Za-z0-9_.-]+$ ]]; then
  echo "ERROR: OWNER/REPO contain characters outside GitHub's naming rules: $OWNER/$REPO" >&2
  exit 1
fi
```

### Step 0: Skip if the PR is already closed

```bash
INITIAL_STATE=$(gh pr view "$PR_NUMBER" --repo "$OWNER/$REPO" --json state -q .state 2>/tmp/wait-pr-close-step0-err.$$)
rc=$?
if [[ $rc -ne 0 || -z "$INITIAL_STATE" ]]; then
  err_msg=$(tail -c 200 /tmp/wait-pr-close-step0-err.$$ 2>/dev/null)
  echo "ERROR: initial state check failed (exit $rc) - last error: ${err_msg:-unknown}" >&2
  rm -f /tmp/wait-pr-close-step0-err.$$
  exit 1
fi
rm -f /tmp/wait-pr-close-step0-err.$$
```

If this fails (auth, repo not found, rate limit), stop here and report the
error — do not fall through and start monitoring as if the PR were open
when the actual state couldn't be determined.

If `INITIAL_STATE` is already `MERGED` or `CLOSED`, skip starting the
monitor and go straight to Step 2 (`/pr-cleanup`).

### Step 1: Start the Monitor

`$OWNER`, `$REPO`, and `$PR_NUMBER` below are placeholders for this
skill's own reasoning, not live shell variables — `Monitor` runs the
`command` string in a fresh shell with none of this conversation's
variables set, so substitute their actual resolved values into the string
literally before calling `Monitor`, the same way `<PR_NUMBER>` in
`description` below is filled in literally.

```bash
Monitor({
  command: "
    fail_count=0
    while true; do
      sleep 30
      state=$(gh pr view \"$PR_NUMBER\" --repo \"$OWNER/$REPO\" --json state -q .state 2>/tmp/wait-pr-close-err.$$)
      rc=$?
      if [[ $rc -ne 0 || -z \"$state\" ]]; then
        err_msg=$(tail -c 200 /tmp/wait-pr-close-err.$$ 2>/dev/null)
        fail_count=$((fail_count + 1))
        if [[ \"$fail_count\" -ge 5 ]]; then
          echo \"WARNING: gh pr view failed 5 times in a row - last error: ${err_msg:-unknown}\"
          fail_count=0
        fi
      else
        fail_count=0
      fi
      rm -f /tmp/wait-pr-close-err.$$
      if [[ \"$state\" == \"MERGED\" || \"$state\" == \"CLOSED\" ]]; then
        echo \"pr_closed state=$state\"
        # Send a Discord notification, same as the old script did
        SCRIPT_DIR=\"$HOME/.claude/scripts/completion-notify\"
        if [[ -x \"$SCRIPT_DIR/send-discord-notification.sh\" ]]; then
          payload=$(jq -n \\
            --arg title \"PR ${state}\" \\
            --arg desc \"PR #${PR_NUMBER} was ${state}.\" \\
            --arg url \"https://github.com/${OWNER}/${REPO}/pull/${PR_NUMBER}\" \\
            '{embeds: [{title: $title, description: $desc, url: $url, color: 3447003}]}')
          printf '%s\\n' \"$payload\" | \"$SCRIPT_DIR/send-discord-notification.sh\"
        fi
        break
      fi
    done
  ",
  description: "PR #<PR_NUMBER> merge/close",
  persistent: true,
})
```

- The loop sleeps before its first `gh pr view` call, so Step 0's check is
  never immediately repeated. No fixed max wait is set —
  `persistent: true` keeps polling until the session ends.
- Each `gh pr view` failure is captured to a per-run temp file so the
  eventual warning can quote the actual error instead of just guessing at
  the cause.
- After 5 consecutive failures (~2.5 minutes), emits one `WARNING` line —
  including the last captured error — to the Monitor's stdout, so a
  failure streak is never silent, then resets the counter and keeps
  polling.

### Step 2: On Detection

When the monitor emits a `pr_closed` event (or Step 0 already found the PR
closed), call `/pr-cleanup https://github.com/$OWNER/$REPO/pull/$PR_NUMBER`
directly in the same conversation.

## Notes

- Do not ask the user for confirmation before starting the monitor.
- This only detects closure while the current session is alive. If the
  session ends first, the monitor is lost — the user must run
  `/pr-cleanup <PR number or URL>` manually later. This mirrors the
  previous tmux-based design's real-world limitation (a terminated tmux
  session could not be revived either), so it is not a regression.
- No lock file / flock is used — Step 0's one-time state check replaces
  it, since a `Monitor` loop only needs to run once per PR within a given
  session.
