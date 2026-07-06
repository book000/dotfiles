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

Resolve `OWNER`, `REPO`, `PR_NUMBER` from the caller's context. Pass the
repository explicitly whenever the target PR lives in a different
repository than the local `origin` (the fork scenario from Issue #171 —
`issue-pr`'s Phase 18 always resolves this as `$ISSUE_OWNER/$ISSUE_REPO`).

### Step 0: Skip if the PR is already closed

```bash
INITIAL_STATE=$(gh pr view "$PR_NUMBER" --repo "$OWNER/$REPO" --json state -q .state)
```

If `INITIAL_STATE` is already `MERGED` or `CLOSED`, skip starting the
monitor and go straight to Step 2 (`/pr-cleanup`).

### Step 1: Start the Monitor

```bash
Monitor({
  command: "
    fail_count=0
    while true; do
      state=$(gh pr view \"$PR_NUMBER\" --repo \"$OWNER/$REPO\" --json state -q .state 2>/dev/null || true)
      if [[ -z \"$state\" ]]; then
        fail_count=$((fail_count + 1))
        if [[ \"$fail_count\" -ge 5 ]]; then
          echo \"WARNING: gh pr view failed 5 times in a row (auth or network issue?)\"
          fail_count=0
        fi
      else
        fail_count=0
      fi
      if [[ \"$state\" == \"MERGED\" || \"$state\" == \"CLOSED\" ]]; then
        echo \"pr_closed state=$state\"
        # Discord 通知（既存のスクリプトと同等）
        SCRIPT_DIR=\"$HOME/.claude/scripts/completion-notify\"
        if [[ -x \"$SCRIPT_DIR/send-discord-notification.sh\" ]]; then
          payload=$(jq -n \\
            --arg title \"PR ${state}\" \\
            --arg desc \"PR #${PR_NUMBER} が ${state} されました。\" \\
            --arg url \"https://github.com/${OWNER}/${REPO}/pull/${PR_NUMBER}\" \\
            '{embeds: [{title: $title, description: $desc, url: $url, color: 3447003}]}')
          printf '%s\\n' \"$payload\" | \"$SCRIPT_DIR/send-discord-notification.sh\"
        fi
        break
      fi
      sleep 30
    done
  ",
  description: "PR #<PR_NUMBER> merge/close",
  persistent: true,
})
```

- `sleep 30` — 30 秒間隔。固定の最大待機時間は設けない
  （`persistent: true` によりセッション終了までポーリングを継続する）。
- `fail_count` により、`gh pr view` が5回連続（約2分半）で失敗した場合に
  Monitor の標準出力へ警告を1行出力する（継続不能な失敗が連続する場合に無限に
  沈黙しないための対応）。

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
