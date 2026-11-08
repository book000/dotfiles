# Sub-Agent Delegation Strategy

**Default: direct action.** Delegate only when overhead is justified.

---

## Decision framework

```
Can I do this in ≤ 5 tool calls?
├─ YES → Do it yourself
└─ NO  → Genuine parallelism or specialization benefit?
    ├─ YES → Delegate
    │   ├─ Other independent work to do? → background mode
    │   └─ No other work?               → sync mode (or just do it yourself)
    └─ NO  → Do it yourself
```

## Quick reference

| Task type | Tool calls | Recommendation |
|---|---|---|
| File read | 1–2 | Direct |
| Simple edit | 2–3 | Direct |
| Single search | 1–2 | Direct |
| Multi-file analysis | 5–10 | Direct with structured approach |
| Cross-module investigation | 10–15 | Explore agent if parallel work exists |
| Full feature implementation | 15+ | general-purpose agent with planning |
| Security / code review | Any | Specialized agent (high signal-to-noise) |
| Claude Code prompt-file maintenance (`CLAUDE.md`, `AGENTS.md`, `rules/*.md`, `docs/*.md`, `skills/*`, `agents/*.md`, hook scripts, `settings.json`) | Any | Always delegate, unless the user explicitly waives delegation for the request — see carve-out below |

## Prompt-file maintenance carve-out

Claude Code's own prompt files (`CLAUDE.md`/`AGENTS.md`, `rules/*.md`, `docs/*.md`, `skills/*`, `agents/*.md`, hooks, `settings.json`) get injected into, or read by, every future session. Reading/editing them from the parent session leaves that exploration sitting in a context that persists for the rest of the conversation — so, regardless of tool-call count, delegate this work to an agent instead of doing it directly, unless the user explicitly waives delegation for the request. Exception: reading a `docs/*.md` file in order to follow it (as the CLAUDE.md Context loading table directs) is not maintenance and is done directly; maintenance and editing are delegated unless the user has explicitly waived delegation for the request.

Parent session's job: define the task, pass along any research/decisions already gathered, review the agent's output, and own all user-facing Q&A (agents can't call `AskUserQuestion` — relay per `~/.claude/docs/design-workflow.md`). Keep direct tool use to quick recon (`ls`/`grep`) for scoping only.

The agent has no memory of this rule file, so the dispatch prompt must restate the concrete scope and task inline — not just reference "this carve-out" by name.

When the prompt files being edited live under a chezmoi-managed dotfiles repo (source at `home/dot_*`, deployed to e.g. `~/.claude/`), always edit the chezmoi SOURCE path, never the deployed target path directly — direct edits to the deployed path get silently overwritten by the next `chezmoi apply`/`chezmoi update` (including automatic/scheduled runs), discarding the edit without warning.

## When to delegate ✅

1. **True parallelism** — independent threads that can run simultaneously.
2. **Specialized expertise** — security review, performance profiling.
3. **Large-scale investigation** — cross-cutting concerns across many modules.
4. **Context isolation** — verbose output or experimental approaches that would pollute main context.

## When NOT to delegate ❌

1. Task accomplishable in ≤ 5 direct tool calls.
2. No real parallel work to do while waiting.
3. High context dependency — frequent back-and-forth with current state.
4. One-off trivial operations (formatting, one-liner fixes).

## Anti-patterns

| Anti-pattern | Bad | Good |
|---|---|---|
| Micro-delegation | Launch agent to read one file | Read the file directly |
| Background polling | Launch background, then immediately block waiting for its result | Continue own work; retrieve on notification |
| Deep chains | A → B → C → D | Keep depth ≤ 2 levels |
| Excessive context passing | Shuttle 200 KB between agents | Keep large context in main, delegate only independent pieces |

## Planner–Generator–Evaluator pattern

For features spanning 5+ files or with security-critical paths:

1. **Planner** (`general-purpose`): break down requirements into subtasks.
2. **Generator** (main agent or worker): implement each subtask.
3. **Evaluator** (`security-review` / `code-review`): verify correctness, security, performance.

## Sub-agent model selection

| Role | Model | Tools |
|---|---|---|
| Coordinator | Opus | All |
| Implementation worker | Sonnet | Write, Edit, Bash |
| Verification worker | Opus | Read, Grep, Bash |
| Discovery worker | Haiku | Read, Grep |

## Handling Idle Notifications from Background Sub-Agents

Whether an `Agent` call runs in the background is set by `run_in_background` (the behavior when it is omitted depends on the harness), so always pass `run_in_background: false` explicitly when you need the result before continuing. A background sub-agent's final message is returned to the parent session when it stops, including when it becomes idle. Read that message to determine whether the task is complete; an idle notification alone does not mean the task is unfinished.

This applies whenever a background-mode sub-agent (explicit `run_in_background: true`, or a harness default of background) sends an idle notification. It does not apply to sync-mode (`run_in_background: false`) dispatches, since those block the calling turn until the sub-agent returns. The `deep-review` and `lite-review` reviewers are launched in sync mode, so this section does not apply to them.

**Follow-up procedure:**

1. If the returned message shows the task is incomplete or its status is unclear, send the sub-agent one `SendMessage` nudge asking it to continue or clarify its status. Do not nudge a sub-agent whose returned message already reports completion.
2. If no completion message arrives within a timeout (default 15 minutes
   since the nudge; a calling skill may define its own threshold — that
   takes precedence over this default), set up a `CronCreate`
   check-in (default: every 15 minutes) if one isn't already running, to
   track outstanding sub-agents. This timeout is purely elapsed wall-clock
   time since the nudge was sent — it applies identically whether the
   sub-agent acknowledged the nudge, produced other output, or gave zero
   response of any kind; do not wait for an acknowledgment before starting
   or continuing this clock.
3. At each check-in, any sub-agent still not completed after its own
   timeout (default 30 minutes since the nudge) is stopped (e.g. via
   `TaskStop`) and re-dispatched once, with the same input — again based
   solely on elapsed time, regardless of whether the sub-agent ever
   responded to the nudge.
4. If the re-dispatch also times out, mark that sub-agent's task as
   **unresolved** in the calling skill's final report — do not silently
   drop it — and move on with the rest of the work instead of waiting
   further.
5. Once every sub-agent is either completed or marked unresolved, delete
   the `CronCreate` check-in with `CronDelete`.

**Notes:**

- `CronCreate` jobs are session-scoped and auto-expire after 7 days (same
  constraint as `check-container-status`'s use of `CronCreate`).
- This rule sets the default cadence and retry count; it does not mandate
  a specific state-tracking mechanism. A calling skill that already tracks
  sub-agent progress (a state file like `STATE.md`, or the `Todo`/`Task`
  tools) may reuse that instead of inventing a new one.

The final message is the result channel: a sub-agent's findings are returned through its final message, and `SendMessage` is not used for the final report. Use `SendMessage` for progress sharing or when a sub-agent needs a response before it can continue; if the final message shows incomplete or unclear status, follow the recovery procedure above.

## Cleanup and long-running work

- After you have consumed a sub-agent's final result, stop it with `TaskStop` if it is still listed as running or idle, and at the end of a multi-agent workflow check `ListAgents` and stop any leftover sub-agents you started.
- Never stop a peer interactive session or a sub-agent you did not start.
- For background work expected to take more than about 5 minutes, state an ETA when you launch it, and post a one-line progress update before any longer wait.
- Answer ETA or "is it stuck?" questions from measured progress (output, checkpoints, `git log`), not from a guess.
- Keep the number of parallel background agents low, and reduce it when the user reports high machine load.
- The timeouts and check-in cron in the Follow-up procedure above also apply to a long-running sub-agent that has not returned a final message: fix the give-up deadline when you launch it.

## Peer cross-session messages

- To reach another session (for example the session that owns a different repository), find it with `ListAgents` and contact it with `SendMessage`.
- Ask the owning session to make changes in its own repository instead of making them from this session.
- Reply to every inbound cross-session message.
