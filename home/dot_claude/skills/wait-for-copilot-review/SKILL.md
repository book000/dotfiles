---
name: wait-for-copilot-review
description: Waits for a GitHub Copilot review after PR creation using the Monitor tool, and automatically triggers /handle-pr-reviews on detection — no tmux required.
argument-hint: "[PR number]"
disable-model-invocation: false
---

# Wait for GitHub Copilot Review

Detects when GitHub Copilot posts a review after PR creation, using the
`Monitor` tool for in-session polling. Do not ask the user for confirmation
before starting this monitor — starting it is a mechanical follow-through
of an already-approved workflow step, not a new decision.

## Usage

```
/wait-for-copilot-review <PR number> [--repo owner/repo]
```

Resolve `OWNER`, `REPO`, `PR_NUMBER` from the caller's context (always pass
`--repo <owner>/<repo>` equivalent explicitly when the PR lives in a
different repository than the local `origin` — the fork scenario from
Issue #171).

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

### Step 0: Skip if a review already exists

Before starting the monitor, check once whether a Copilot review is
already present — this replaces the old flock-based multi-instance guard,
since a `Monitor` polling loop only needs to exist once per PR within a
session:

```bash
EXISTING=$(gh api graphql \
  -f owner="$OWNER" -f repo="$REPO" -F number="$PR_NUMBER" \
  -f query='query($owner: String!, $repo: String!, $number: Int!) {
    repository(owner: $owner, name: $repo) {
      pullRequest(number: $number) {
        reviews(first: 100) {
          nodes { author { login __typename } state submittedAt }
        }
      }
    }
  }' \
  --jq '[.data.repository.pullRequest.reviews.nodes[]
    | select(.author.__typename == "Bot"
        and (.author.login | contains("copilot"))
        and (.state == "COMMENTED" or .state == "APPROVED")
        and .submittedAt != null)] | length' 2>/tmp/wait-copilot-review-step0-err.$$)
rc=$?
if [[ $rc -ne 0 || -z "$EXISTING" ]]; then
  err_msg=$(tail -c 200 /tmp/wait-copilot-review-step0-err.$$ 2>/dev/null)
  echo "WARNING: initial existing-review check failed (exit $rc) - last error: ${err_msg:-unknown}. Proceeding to start the monitor anyway." >&2
fi
rm -f /tmp/wait-copilot-review-step0-err.$$
EXISTING="${EXISTING:-0}"
```

If `EXISTING` is greater than 0, skip starting the monitor entirely and go
straight to calling `/handle-pr-reviews` (Step 2) — a review is already
there. If the check itself failed, the warning above explains why — do not
silently treat a failed check the same as "no review yet" without surfacing
it.

### Step 1: Start the Monitor

`$OWNER`, `$REPO`, `$PR_NUMBER`, and `$EXISTING` below are placeholders for
this skill's own reasoning, not live shell variables — `Monitor` runs the
`command` string in a fresh shell with none of this conversation's
variables set, so substitute their actual resolved values into the string
literally before calling `Monitor`, the same way `<PR_NUMBER>` in
`description` below is filled in literally.

```bash
Monitor({
  command: "
    last_count=\"$EXISTING\"
    fail_count=0
    while true; do
      sleep 30
      count=$(gh api graphql \\
        -f owner=\"$OWNER\" -f repo=\"$REPO\" -F number=\"$PR_NUMBER\" \\
        -f query='query($owner: String!, $repo: String!, $number: Int!) {
          repository(owner: $owner, name: $repo) {
            pullRequest(number: $number) {
              reviews(first: 100) {
                nodes { author { login __typename } state submittedAt }
              }
            }
          }
        }' \\
        --jq '[.data.repository.pullRequest.reviews.nodes[]
          | select(.author.__typename == \"Bot\"
              and (.author.login | contains(\"copilot\"))
              and (.state == \"COMMENTED\" or .state == \"APPROVED\")
              and .submittedAt != null)] | length' 2>/tmp/wait-copilot-review-err.$$)
      rc=$?
      if [[ $rc -ne 0 || -z \"$count\" ]]; then
        err_msg=$(tail -c 200 /tmp/wait-copilot-review-err.$$ 2>/dev/null)
        fail_count=$((fail_count + 1))
        if [[ \"$fail_count\" -ge 5 ]]; then
          echo \"WARNING: gh api graphql failed 5 times in a row - last error: ${err_msg:-unknown}\"
          fail_count=0
        fi
      else
        fail_count=0
      fi
      rm -f /tmp/wait-copilot-review-err.$$
      if [[ -n \"$count\" && \"$count\" -gt \"$last_count\" ]]; then
        echo \"copilot_review_detected count=$count\"
        # Send a Discord notification, same as the old script did
        SCRIPT_DIR=\"$HOME/.claude/scripts/completion-notify\"
        if [[ -x \"$SCRIPT_DIR/send-discord-notification.sh\" ]]; then
          payload=$(jq -n \\
            --arg title \"GitHub Copilot Review Detected\" \\
            --arg desc \"A Copilot review was posted on PR #${PR_NUMBER}.\" \\
            --arg url \"https://github.com/${OWNER}/${REPO}/pull/${PR_NUMBER}\" \\
            '{embeds: [{title: $title, description: $desc, url: $url, color: 3447003}]}')
          printf '%s\\n' \"$payload\" | \"$SCRIPT_DIR/send-discord-notification.sh\"
        fi
        break
      fi
      last_count=\"${count:-$last_count}\"
    done
  ",
  description: "Copilot review on PR #<PR_NUMBER>",
  persistent: true,
})
```

- `last_count` starts at `EXISTING` (already fetched in Step 0), and the
  loop sleeps before its first query, so Step 0's query is never repeated
  immediately.
- Each `gh api graphql` failure is captured to a per-run temp file so the
  eventual warning can quote the actual error instead of just guessing at
  the cause.
- Polls every 30 seconds, out of consideration for the GitHub API rate
  limit.
- After 5 consecutive failures (~2.5 minutes), emits one `WARNING` line —
  including the last captured error — to the Monitor's stdout, so a
  failure streak is never silent, then resets the counter and keeps
  polling.
- The loop `break`s immediately after emitting `copilot_review_detected` —
  it exists to catch the first Copilot review, not to keep re-triggering
  `/handle-pr-reviews` for every later review or re-review on the same PR.

### Step 2: On Detection

When the monitor emits a `copilot_review_detected` event, call
`/handle-pr-reviews https://github.com/$OWNER/$REPO/pull/$PR_NUMBER`
directly in the same conversation. No tmux, no separate process — the
event arrives in this conversation and this conversation acts on it.

## Notes

- Do not ask the user for confirmation before starting the monitor.
- If the session ends before a review is detected, the monitor is lost —
  the user (or a later session) must run `/handle-pr-reviews` manually.
  This is an accepted limitation (see the design spec for rationale).
- No lock file / flock is used — Step 0's one-time existence check replaces
  it, since a `Monitor` loop only needs to run once per PR within a given
  session.
