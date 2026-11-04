---
name: pr-health-monitor
description: Use right after creating a PR to check its body, CI, conflicts, and reviews, and to start a resumable PR monitor. Only for explicit `$pr-health-monitor` invocations.
---

# PR Health Monitor

`$pr-health-monitor <PR number or URL>` drives the post-PR checks and only observes, recording events in the XDG state. The watcher is observation-only and never runs cleanup, Git changes, or callbacks. Follow-up actions are performed only by `$resume-pr-monitor`.

Start the monitor immediately after the PR is created. The preflight before PR creation is non-mutating and only verifies the launch capability or the fallback to be used. Registering the pane, creating the state/window, and starting the watcher are done by this skill after the canonical PR URL has been obtained.

## Usage

- `$pr-health-monitor <PR number or URL>`

## Steps

1. Resolve the PR.
   - For a bare number, prefer `gh-pr-target-repo.sh`, then the GitHub `upstream` remote.
   - Use the `url` obtained from `gh pr view` as the canonical `PR_URL`, and pass only this URL to the state/watcher.
2. Initialize the monitor after obtaining the canonical `PR_URL`.

   - Always initialize the state first.
   - The resolver safely and uniquely selects the tmux pane that corresponds to the current Codex. A valid direct `TMUX_PANE` is used as is; otherwise only the pane that uniquely corresponds via the parent process chain is selected.
   - Only when the resolver succeeds, register a random nonce of at least 16 characters and start the watcher. `start` launches a supervisor in a dedicated tmux window, which keeps running the observer and the dispatcher.
   - Keep the readiness check of `start` and the fail-closed fallback to `foreground_required` on failure, as described below.

   ```bash
   ~/.agents/skills/pr-health-monitor/scripts/pr-monitor-state.sh init --pr-url "$PR_URL"
   if pane=$(~/.agents/skills/pr-health-monitor/scripts/resolve-tmux-pane.sh); then
       nonce=$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')
       ~/.agents/skills/pr-health-monitor/scripts/pr-monitor-state.sh register-pane --pr-url "$PR_URL" --pane "$pane" --nonce "$nonce"
       ~/.agents/skills/pr-health-monitor/scripts/watch-pr.sh start --pr-url "$PR_URL"
   else
       ~/.agents/skills/pr-health-monitor/scripts/pr-monitor-state.sh watcher-error --pr-url "$PR_URL" --reason foreground_required --expected-pid none || true
       echo "Error: tmux pane registration is unavailable for $PR_URL. Run \$resume-pr-monitor $PR_URL." >&2
       exit 1
   fi
   ```

   `start` does not count as successful merely because the dedicated window was created. The parent passes a per-launch random token to the supervisor, and the child records the token, PID, and process identity in the live lock owner metadata. After obtaining the window ID, wait within a bounded interval for a live lock with the same launch token and a state with the same PID, and report active only when both are confirmed. If confirmation fails, stop that window, do not overwrite an active watcher from another launch, and record `foreground_required` and a clear of the watcher PID.

   - Treat a monitor initialization failure as incomplete/unmonitored. Do not report it as complete or monitoring.
   - The failure report includes the canonical PR URL, the failed stage, fresh evidence, and the exact recovery command `$resume-pr-monitor <PR_URL>`. If the state is writable, record `foreground_required`.
   - Report the watcher as active even if the initial CI/review observation fails after start succeeds. Do not add or overwrite `foreground_required`, and never report an active watcher as incomplete/unmonitored.
   - Report an initial observation failure separately from the active watcher. The failure report includes the canonical PR URL, the failed stage, fresh evidence, and the exact recovery command `$resume-pr-monitor <PR_URL>`. If there is not yet fresh GitHub access, explicitly schedule that resume.

   ```bash
   ~/.agents/skills/pr-health-monitor/scripts/watch-pr.sh watch --pr-url "$PR_URL"
   ```

   The state stores only minimal PR metadata and pending/acknowledged events under `${XDG_STATE_HOME:-~/.local/state}/codex-pr-monitor/`, and an atomic lock prevents duplicate watchers. The GlitchTip callback descriptor is not stored in state. If a foreground terminal is unavailable, do not stop the health check; run `$resume-pr-monitor <PR_URL>`. When using ChatGPT Desktop/Web Scheduled Tasks, also schedule the resume in the project context, and do not treat it as running a local shell detached.
3. Update the PR body to the current status. Before updating, fetch the current body with `gh pr view "$PR_URL" --json body` and preserve the required existing links (especially `GlitchTip Issue: <permalink URL>`). The body contains only the overview, the changes, the verification performed, the current CI/review status, and prerequisites/unresolved items; do not list an update history.
4. Check the initial conflicts and CI with `gh pr view "$PR_URL" --json mergeable,mergeStateStatus` and `gh pr checks "$PR_URL" --watch`. On failure, investigate the cause with `gh run view <RUN_ID> --log-failed`. The watcher also records CI failures/conflicts as durable events.
5. Run the Codex local review.
   - Get head/base with `gh pr view "$PR_URL" --json headRefName,baseRefName`.
   - Confirm with `git remote -v` and the branch that the current worktree corresponds to the target PR's repository and head. Do not guess and run fixes or `codex review` in a worktree that does not correspond.
   - Only when it corresponds, check the base ref on the target remote, run `git fetch <target-remote> <base-ref>` if needed, and use `codex review --base <target-remote>/<base-ref>`. Do not hard-code `origin/master`.
   - If there is no corresponding checkout, report that fact, and rerun after preparing a clone/worktree that explicitly names the target repository. Checking the PR diff and review threads may continue, but no local fixes are made.
6. Request a review with `request-review-copilot` only when it is available. Copilot observation is integrated into the watcher, so do not start `wait-for-copilot-review.sh` in the background.
7. Report the status of CI, conflicts, the body, the local review, the Copilot request, and the tmux monitor, or the resume fallback. Report only fresh evidence. Do not treat past watcher events as the current state until they can be rechecked against fresh GitHub state. The dispatcher sends the fixed `$resume-pr-monitor` prompt only to a pane that the lifecycle hook has recorded as `ready`. The input-mixing race when the user starts typing after ready is a known constraint accepted by the user.
   - If no Copilot review was requested or the request failed, evaluate the ready conditions now (when a Copilot review was requested, `$resume-pr-monitor` evaluates them after handling it). Mark the PR ready (`gh pr ready <PR> --repo <owner/repo>`) only when all hold: (1) the PR is a draft (`gh pr view --json isDraft`) and the user has not asked to keep it as a draft; (2) no merge conflict (`mergeable` is `MERGEABLE`); (3) all review threads are resolved, and a requested Copilot review has been received and handled (waived if the request failed or Copilot is unavailable); (4) no further edits are needed (no uncommitted changes, no unpushed commits, no pending follow-ups). If the PR is already ready, do nothing. If `gh pr ready` fails, leave the PR as a draft and report the reason. Before editing, committing, or pushing to the branch of a PR that is already ready, you MUST first run `gh pr ready <PR> --undo --repo <owner/repo>` to return it to draft. If `gh pr ready --undo` fails, or you cannot confirm the PR is a draft again (e.g. via `gh pr view --json isDraft`), do not edit, commit, or push; report the failure instead. Mark it ready again only when the conditions above hold. Never merge.

## Boundaries

- The watcher polls the PR state, checks, conversation comments, reviews, and review comments regardless of actor at a 30-second interval (changeable via `PR_MONITOR_INTERVAL` for tests only), and stops on 5 consecutive API failures.
- `MERGED`/`CLOSED`, CI failure, conflict, and review feedback are each recorded once per transition. Detected review feedback is delivered to `$handle-pr-reviews`. The action processor acquires an event lease and acknowledges only after success, so unprocessed state is not lost across sessions.
- The local state holds no GlitchTip callback authority. GlitchTip Resolve is performed only in a verified flow that the user explicitly requested, after re-checking the issue, permalink, and PR body.
