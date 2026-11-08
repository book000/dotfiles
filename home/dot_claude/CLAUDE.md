## Guardrails

- No unauthorized changes (hooks, settings, PRs) without explicit approval — ask if blocked.
- Work carefully and thoroughly, no shortcuts regardless of scale.
- **Do not merge PRs until explicitly instructed.**
- **Delegate all reading/writing of Claude Code's own prompt files** (`CLAUDE.md`/`AGENTS.md`, `rules/*.md`, `docs/*.md`, `skills/*`, `agents/*.md`, hooks, `settings.json`) to a sub-agent, regardless of task size, unless the user explicitly waives delegation for the request (reading a `docs/*.md` file to follow it, as Context loading directs, is not maintenance and is done directly) — see `~/.claude/docs/workflow-sub-agents.md` for detail.
- **Before creating any PR, run the pre-PR review (local diff mode) and complete the Pre-PR checklist in `~/.claude/docs/workflow.md`** — never skip it. Doc-only diffs and small diffs (≤ 5 files and ≤ 150 changed lines, excluding lockfiles) use `/lite-review` (report-only on a local diff, so fix its merge-blocker findings yourself); everything else uses `/deep-review --fix`. The lite paths (`issue-pr-lite`, `glitchtip-pr-lite`) always run `/lite-review`.

## Behavior

- No flattery. Push back when warranted. Be concise.
- Use **AskUserQuestion** for all clarifying questions directed at the user. Do not ask questions as plain text.
- Do not ask permission to proceed, and do not hand a judgment you can make yourself back to the user, except where a guardrail or skill approval gate requires explicit approval.
- State conclusions only from logs, command output or source you have read; mark anything else unverified and run the check instead of ending on a hypothesis.
- Verify a done/success status against the real outcome, not the status label.

## Language

- Respond in Japanese. Intermediate steps in English to save context. This is independent of the language of deliverables (commit descriptions, PR/Issue titles, bodies and review comments, code comments/docstrings, documents, spec/plan posts). Report times in JST.
- Deliverable language: the target repository's own convention wins. The nearest `AGENTS.md`/`CLAUDE.md` covering the target path wins over the root one; within one scope check, in order, `AGENTS.md`, `CLAUDE.md`, then `.github/copilot-instructions.md` and similar. Resolve per deliverable type (commit descriptions, PR/Issue text, code comments, documents): use the first file that specifies that type, and consult lower-priority files only for types it leaves unspecified.
- No convention, or an ambiguous one: ask the user via AskUserQuestion. Never infer from owner, organization, visibility, or README language, and a visibility change alone never changes it. For a new repository, ask and record the answer in a concise `AGENTS.md`. Once the user has answered or `AGENTS.md` records the language, reuse it and do not ask again unless the user changes it.
- Non-interactive runs: do not decide the language or create/rewrite `AGENTS.md`. Defer only language-dependent deliverables and report the language as undetermined; reading, investigation and tests may continue.
- Exceptions: localized UI strings, quotations, technical identifiers, generated files, external source text. Never rewrite Git history.
- Error messages: English unless the repository convention says otherwise.
- Half-width space between Japanese and alphanumeric characters.
- **All Markdown under `~/.claude/` must be written in English.**
- **No mid-sentence line breaks**: within a single prose paragraph (chat responses, generated Markdown documents/articles, PR/commit/comment bodies, etc.), do not insert a manual line break (hard-wrapping, e.g. at a fixed column width) in the middle of a sentence. Write each sentence as one continuous line in the source text; let the renderer wrap it. This applies to prose paragraphs, not to intentionally structured content (bullet lists, code blocks, tables), where one item/line per line is expected.

## Git

- Push via **SSH** only. Handle auth autonomously.
- Commits: [Conventional Commits](https://www.conventionalcommits.org/) — description language follows the repository language convention (see Language).
- Branches: [Conventional Branch](https://conventional-branch.github.io) short-form (`feat`, `fix`, …).
- Do not modify `GH_CONFIG_DIR`, `GIT_*`, or `GIT_SSH_COMMAND` env vars without permission.
- No `git config` username/email changes.
- No commits to Renovate-created PRs.
- Before editing, committing, or pushing to the branch of a PR that is marked ready for review, you MUST first run `gh pr ready <PR> --undo --repo <owner/repo>` to return it to draft. If `gh pr ready --undo` fails, or you cannot confirm the PR is a draft again (e.g. via `gh pr view --json isDraft`), do not edit, commit, or push; report the failure instead. Mark it ready again only when the existing ready conditions hold. CI state is not a ready condition: mark it ready as soon as the conditions hold, and if CI fails afterwards, return it to draft with `--undo` and fix it.
- Clone repos to a temp dir for research.
- After creating a PR (skill or ad-hoc `gh pr create`), run `/pr-health-monitor <PR URL>` before reporting completion; see the Post-PR checklist in `~/.claude/docs/workflow.md`.

## Skills

| Skill | Purpose |
|---|---|
| `/issue-pr <number>` | Issue → implementation → PR |
| `/ticket-pr <key or URL>` | Jira ticket → implementation → PR |
| `/glitchtip-pr [issue-id or URL]` | GlitchTip issue → implementation → PR → auto-resolve on merge |
| `/pr-health-monitor <number>` | Post-PR: CI result, Copilot/human review feedback, merge/close, conflicts in one Monitor (max 3h) |

## Context loading

Auto-loaded: this file, `rules/security.md`, and the path-gated `rules/*.md` (`coding-*`, `context7`) when matching files are touched. The `~/.claude/docs/*.md` files are not auto-loaded — Read the relevant one only when the situation applies:

| When | Read |
|---|---|
| Checklists / Jira / GlitchTip / production operations / Oracle rules needed | `~/.claude/docs/workflow.md` |
| Deciding whether or how to delegate to a sub-agent | `~/.claude/docs/workflow-sub-agents.md` |
| An idle notification arrives from a background sub-agent | `~/.claude/docs/workflow-sub-agents.md` ("Handling Idle Notifications from Background Sub-Agents" section) |
| Writing/reviewing code, comments, tests, commits | `~/.claude/rules/coding-common.md` |
| Writing a spec or plan document | `~/.claude/docs/design-workflow.md` |
| Posting a spec/plan/investigation doc to a GitHub Issue | `~/.claude/docs/issue-comment-docs.md` |
| Posting a spec/plan/investigation doc not tied to a GitHub Issue | `trilium` skill (invoke via Skill tool) |
| Using an `rtk` meta command (`gain`, `discover`, `proxy`) | `rtk` skill |

## Tracking

Use the Todo tool for work with 3 or more steps, and keep it current: mark each task `in_progress` when starting and `completed` when done.

## Gotchas

- Background monitoring: notify tmux on end/error — `tmux send-keys -t "$SESSION" "msg" && sleep 3 && tmux send-keys -t "$SESSION" Enter`
- A Bash command that starts with `sleep N` followed by another command is blocked by the harness: wait with `run_in_background`, or Monitor with `until <check>; do sleep 2; done`.
- `<<'EOF'` heredocs: backticks must be literal `` ` `` — `\`` outputs two characters in GitHub Markdown.
- chezmoi: `executable_` prefix is stripped at deploy — reference scripts without it in settings/configs.

@CLAUDE.local.md
