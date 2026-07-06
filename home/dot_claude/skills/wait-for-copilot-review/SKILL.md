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

Resolve `OWNER`, `REPO`, `PR_NUMBER` from the caller's context (always pass
`--repo <owner>/<repo>` equivalent explicitly when the PR lives in a
different repository than the local `origin` — the fork scenario from
Issue #171).

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
        and .submittedAt != null)] | length')
```

If `EXISTING` is greater than 0, skip starting the monitor entirely and go
straight to calling `/handle-pr-reviews` (Step 2) — a review is already
there.

### Step 1: Start the Monitor

```bash
Monitor({
  command: "
    last_count=\"${EXISTING:-0}\"
    fail_count=0
    while true; do
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
              and .submittedAt != null)] | length' 2>/dev/null || true)
      if [[ -z \"$count\" ]]; then
        fail_count=$((fail_count + 1))
        if [[ \"$fail_count\" -ge 5 ]]; then
          echo \"WARNING: gh api graphql failed 5 times in a row (auth or network issue?)\"
          fail_count=0
        fi
      else
        fail_count=0
      fi
      if [[ -n \"$count\" && \"$count\" -gt \"$last_count\" ]]; then
        echo \"copilot_review_detected count=$count\"
        # Discord 通知（既存のスクリプトと同等）
        SCRIPT_DIR=\"$HOME/.claude/scripts/completion-notify\"
        if [[ -x \"$SCRIPT_DIR/send-discord-notification.sh\" ]]; then
          payload=$(jq -n \\
            --arg title \"GitHub Copilot Review Detected\" \\
            --arg desc \"PR #${PR_NUMBER} に Copilot レビューが投稿されました。\" \\
            --arg url \"https://github.com/${OWNER}/${REPO}/pull/${PR_NUMBER}\" \\
            '{embeds: [{title: $title, description: $desc, url: $url, color: 3447003}]}')
          printf '%s\\n' \"$payload\" | \"$SCRIPT_DIR/send-discord-notification.sh\"
        fi
      fi
      last_count=\"${count:-$last_count}\"
      sleep 30
    done
  ",
  description: "Copilot review on PR #<PR_NUMBER>",
  persistent: true,
})
```

- `${EXISTING:-0}` により、Step 0 で既に確認済みの件数を初期値として渡す。
- API 呼び出しは `|| true` で失敗時もループを継続する。
- `sleep 30` — 30 秒間隔（GitHub API のレート制限を考慮）。
- `fail_count` により、`gh api graphql` が5回連続（約2分半）で失敗した場合に
  Monitor の標準出力へ警告を1行出力する（継続不能な失敗が連続する場合に無限に
  沈黙しないための対応）。

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
