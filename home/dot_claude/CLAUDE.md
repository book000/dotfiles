## Guardrails

- No unauthorized changes (hooks, settings, PRs) without explicit approval — ask if blocked.
- Work carefully and thoroughly, no shortcuts regardless of scale.
- **Do not merge PRs until explicitly instructed.**

## Behavior

- No flattery. Push back when warranted. Be concise.
- Use **AskUserQuestion** for all clarifying questions directed at the user. Do not ask questions as plain text.

## Language

- Respond in Japanese. Intermediate steps in English to save context.
- Code comments: follow project CLAUDE.md; default English. Error messages: English.
- Half-width space between Japanese and alphanumeric characters.
- **All Markdown under `~/.claude/` must be written in English.**
- **No mid-sentence line breaks**: within a single prose paragraph (chat responses, generated Markdown documents/articles, PR/commit/comment bodies, etc.), do not insert a manual line break (hard-wrapping, e.g. at a fixed column width) in the middle of a sentence. Write each sentence as one continuous line in the source text; let the renderer wrap it. This applies to prose paragraphs, not to intentionally structured content (bullet lists, code blocks, tables), where one item/line per line is expected.

## Git

- Push via **SSH** only. Handle auth autonomously.
- Commits: [Conventional Commits](https://www.conventionalcommits.org/) — description language follows project CLAUDE.md, otherwise Japanese.
- Branches: [Conventional Branch](https://conventional-branch.github.io) short-form (`feat`, `fix`, …).
- Do not modify `GH_CONFIG_DIR`, `GIT_*`, or `GIT_SSH_COMMAND` env vars without permission.
- No `git config` username/email changes.
- No commits to Renovate-created PRs.
- Clone repos to a temp dir for research.

## Skills

| Skill | Purpose |
|---|---|
| `/issue-pr <number>` | Issue → implementation → PR |
| `/ticket-pr <key or URL>` | Jira ticket → implementation → PR |
| `/pr-health-monitor <number>` | Post-PR: CI, Copilot review, conflicts |
| `/handle-pr-reviews <URL>` | Reply and resolve review threads |
| `/wait-for-copilot-review <number>` | Background wait for Copilot review |

## Context loading

Not auto-loaded. Read the relevant file only when the situation applies:

| When | Read |
|---|---|
| Checklists / Jira rules needed | `rules/workflow.md` |
| Deciding whether to delegate to a sub-agent (esp. any work touching Claude Code's own prompt files: `CLAUDE.md`/`AGENTS.md`, `rules/*.md`, `skills/*`, `agents/*.md`, hooks, `settings.json`) | `rules/workflow-sub-agents.md` |
| Writing/reviewing code, comments, tests, commits | `rules/coding-common.md` |
| Writing a spec or plan document | `rules/superpowers.md` |
| Posting a spec/plan/investigation doc to a GitHub Issue | `rules/issue-comment-docs.md` |
| Posting a spec/plan/investigation doc not tied to a GitHub Issue | `trilium` skill (invoke via Skill tool) |
| Using an `rtk` meta command (`gain`, `discover`, `proxy`) | `rtk` skill |

## Tracking

Use the Todo tool for all multi-step work without omission.

## Gotchas

- Background monitoring: notify tmux on end/error — `tmux send-keys -t "$SESSION" "msg" && sleep 3 && tmux send-keys -t "$SESSION" Enter`
- `<<'EOF'` heredocs: backticks must be literal `` ` `` — `\`` outputs two characters in GitHub Markdown.
- chezmoi: `executable_` prefix is stripped at deploy — reference scripts without it in settings/configs.

@CLAUDE.local.md
