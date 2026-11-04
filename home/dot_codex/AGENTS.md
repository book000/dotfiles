## Core Principles

- Do not change hooks, settings, or PRs without the user's explicit approval. Do not merge a PR until explicitly instructed.
- State assumptions and uncertainty, and ask when an ambiguity makes the implementation risky. Verify external specifications against primary sources.
- Reply to the user in Japanese; keep intermediate steps in concise English. This is independent of the language of deliverables (commit descriptions, PR/Issue titles, bodies and review comments, code comments/docstrings, documents, spec/plan posts).
- Deliverable language: the target repository's own convention wins. `AGENTS.md` files are concatenated root to cwd and a deeper one overrides, so the nearest `AGENTS.md` covering the target path wins over the root one; within one scope check, in order, `AGENTS.md`, `CLAUDE.md`, then `.github/copilot-instructions.md` and similar. Resolve per deliverable type (commit descriptions, PR/Issue text, code comments, documents): use the first file that specifies that type, and consult lower-priority files only for types it leaves unspecified; a mismatch with a lower-priority file is not a reason to treat the language as undetermined. Explicitly check the nearest `AGENTS.md` and the repository root `AGENTS.md` when determining the language.
- No convention, or an ambiguous one: when interactive, ask the user with `request_user_input` if available, otherwise ask directly in plain text, and do not choose a language before the answer. Never infer the language from the owner, organization, visibility, or README language, and a visibility change alone never changes it. For a new repository, ask and record the answer in a concise `AGENTS.md`. Once the user has answered or `AGENTS.md` records the language, reuse it and do not ask again unless the user changes it.
- Non-interactive runs: do not decide the language and do not create or rewrite `AGENTS.md`. Defer only language-dependent deliverables and report the language as undetermined; reading, investigation and tests may continue.
- Exceptions: localized UI strings, quotations, technical identifiers, generated files, and external source text. Never rewrite Git history. Write error messages in English unless the repository convention says otherwise. Insert a half-width space between Japanese and alphanumeric characters.
- Record decisions in GitHub Issue comments or the PR body, not in local Markdown files. The exception is a durable repository convention explicitly intended for `AGENTS.md`, such as the language convention for a new repository.
- All Markdown under `~/.codex/` must be written in English.
- When the target of reading or writing is Codex's own instructions, skills, hooks, or settings, delegate to a subagent to isolate the blast radius. For chezmoi-managed files, update the source under `home/`, not the deployed copy.
- For work that spans multiple stages or runs long enough that compaction is likely, record a resume checkpoint in a GitHub Issue comment before the conversation grows long. It is unnecessary for trivial work that finishes quickly. The checkpoint concisely includes the goal and acceptance criteria, decisions and assumptions, branch and worktree state and changed paths, completed work and verification results, open items and blockers, and the concrete next action; it never includes secrets or raw logs. Do not guess the exact compaction point; record before important state would be lost. After compaction, re-read the checkpoint and verify the current repository and GitHub state before continuing, and do not treat stale statements as fact. For work not tied to an Issue, do not create a local Markdown checkpoint; record the same key points in a concise assistant conversation message before compaction, re-read that message after compaction, and re-verify the repository state.
- Do not use `command_relay_mcp`. Try SSH to reach remote machines, and use the `gh` CLI, not MCP, to read or operate on GitHub. Available aliases differ per environment, so do not assume they are discoverable.

## Git and PRs

- Use Conventional Branch short forms for branches and Conventional Commits for commits.
- Push over SSH. Do not change `GH_CONFIG_DIR`, `GIT_*`, or `GIT_SSH_COMMAND` without permission, and do not change the Git username/email. Do not commit to PRs created by Renovate.
- When SSH reports `Bad owner or permissions on ...ssh_config...`, check the owner and permissions of the target file and the symlink target with `id` and `stat -L`, and run `ssh -G <host>` to tell whether the failure is in the config-loading stage. Do not assert without evidence that the Codex sandbox is the cause. `ssh -F "$HOME/.ssh/config"` skips the system-wide `/etc/ssh/ssh_config`, so do not use `-F /dev/null` / `none`. Only when the per-user config resolves the target host/alias and any needed system-wide aliases, known hosts, crypto policy, etc. are configured equivalently or confirmed unnecessary, run `ssh -F "$HOME/.ssh/config" -G <host>` and a read-only connection check. If that cannot be confirmed or the check fails, do not bypass the configuration; report the evidence and the error. If Git needs the same workaround and the conditions are confirmed, apply it to that command only with `git -c core.sshCommand="ssh -F \"$HOME/.ssh/config\"" <operation>`. Do not change environment variables, persistent SSH/Git configuration, file ownership or permissions, or the sandbox mode.
- Before implementing, check the repository layout, the working branch, the latest remote default branch, unneeded local branches, and required dependencies. Clone GitHub repositories you only investigate into a temporary directory.
- Before committing, check for secrets, lint/format errors, the required verification, and the expected behavior.
- Before creating a PR, check the user's request, secrets, conflict risk, and a local code review appropriate to the change. Prefer `gh-pr-target-repo.sh` to choose the PR target, and default to the GitHub `upstream` remote if one exists.
- The PR body states only the current state and does not list update history.
- Create the PR as a draft (`gh pr create --draft`) when follow-up edits are expected (Copilot review handling, review-thread handling, Jira/GlitchTip follow-up commits) unless the user asks otherwise. `$pr-health-monitor` / `$resume-pr-monitor` run `gh pr ready <PR> --repo <owner/repo>` only when there is no conflict, all review threads are resolved with any requested Copilot review handled, and no further edits are needed. Before editing, committing, or pushing to the branch of a PR that is marked ready for review, you MUST first run `gh pr ready <PR> --undo --repo <owner/repo>` to return it to draft. If `gh pr ready --undo` fails, or you cannot confirm the PR is a draft again (e.g. via `gh pr view --json isDraft`), do not edit, commit, or push; report the failure instead. Mark it ready again only when the existing ready conditions hold. Never merge.
- PR creation is fail-closed on monitoring. The monitor preflight before PR creation is non-mutating: do not register a pane, create state or a window, or start the watcher until the canonical PR URL is obtained. Before `gh pr create`, select and keep a persistent terminal or the `$resume-pr-monitor <PR URL>` fallback. If neither a persistent terminal nor the resume fallback can be selected, do not create the PR and stop. If the monitor fails, report incomplete/unmonitored with the canonical PR URL, the failed stage, fresh evidence, and the exact recovery command `$resume-pr-monitor <canonical PR URL>`, and never report complete, monitoring, or deployment-ready. Details are in `$issue-pr` and `$pr-health-monitor`.
- The final gate right before PR creation is fail-closed: record one reviewed snapshot (HEAD, the index, the worktree's tracked, staged, and untracked state, and evidence IDs), and never re-capture or update it. If the diff, status, or evidence changes, restart the entire final gate from the beginning. A deployment assertion, including commit, PR creation, and deployment-ready/deployed, may be made only immediately after confirming the final evidence against this reviewed snapshot. Stop if there are unresolved findings of 50 or more, P1, or P2, a verification failure, a secret, or an unintended diff. Details are in `$issue-pr` and `$pr-health-monitor`.
- When one PR covers multiple Issues, verify that every Issue is unique, open, and belongs to the target repository, and do not create the PR until all Issues pass the aggregate final gate (scope and acceptance criteria, required documents, review evidence, and closing keyword per Issue). `Closes #<issue>` in the PR body must contain a closing keyword and list exactly the verified Issues only. Details are in `$issue-pr`.

## Implementation and Verification

- Match the existing structure and naming, and do not duplicate in comments what the code already makes clear. Aim for zero code comments: first express intent through naming, types, structure, or tests, and keep a comment only for a reason, constraint, dangerous assumption, or why-not the code cannot show, as a conclusion in 1-2 lines as a guideline. Never narrate the work or leave change history, deliberation, Issue/PR numbers, spec/plan paths, or verification steps. JSDoc/docstrings are separate API contracts, written only when they add contract value. Machine-readable comments a tool requires and lint/type-check suppression reasons are out of scope.
- When changing the repository layout, usage instructions, tests, or security policy, check whether the README, the project instructions, and the Copilot instructions need updating.
- Run the syntax, unit, and integration tests that correspond to the change. When a notification, hook, or helper is changed or removed, also check the references inside the tests.
- In chezmoi, the `executable_` prefix is stripped on deployment. When a configuration references a script, use the deployed name.

## Additional Guidance

- When handling the API, configuration, compatibility, deprecation, or version differences of an external library or framework, determine the target version from the project's lockfile or similar and verify against primary sources. If it cannot be determined, state that it is unknown and show the branches.
- Use the `request_user_input` tool to ask the user. When a requirement can be interpreted in several ways, do not choose on your own.
- Do not insert a manual line break in the middle of a prose paragraph, in Markdown, chat responses, or PR/commit/comment bodies. Bullet lists, tables, headings, and code blocks are exempt from this constraint.
- Post specs, plans, and investigation artifacts tied to a GitHub Issue as Issue comments after checking for secrets, and report only the URL after posting. Use separate comments for separate documents, and specify the comment ID when updating. For documents unrelated to an Issue, follow an available skill or the user's instructions for where to save them.
- After creating or updating `.agent-work/specs/` or `.agent-work/plans/`, and before presenting it to the user, ask the `spec_reviewer` or `plan_reviewer` agent to review and fix it. If these local artifacts are ignored, do not force-add them.

Read the following references first, depending on the change target.

| Target | Reference |
| --- | --- |
| Common code quality, secrets, destructive operations, dependencies, input handling | `~/.codex/references/coding-and-security.md` |
| TypeScript / JavaScript | `~/.codex/references/typescript-javascript.md` |
| Python, Shell, Dockerfile | `~/.codex/references/python-shell-docker.md` |
| C#, `.csproj`, `.sln`, `.editorconfig` | `~/.codex/references/csharp.md` |
| GitHub Actions workflow | `~/.codex/references/github-actions.md` |
| GitHub Issue documents, Jira, GlitchTip, agent delegation | `~/.codex/references/workflow.md` |

## Codex Skills

Codex CLI provides command-equivalent workflows as skills, not arbitrary custom slash commands. Codex loads skills from the repo, user, admin, and system scopes. This dotfiles repository manages the user-scope `~/.agents/skills`.

- Skills managed by this dotfiles repository are placed in `~/.agents/skills`.
- Invoke a skill explicitly with `$` followed by its name.
- `$issue-pr`: from a GitHub Issue, implement, create a PR, and start the post-PR flow.
- `$ticket-pr`: from a Jira ticket, implement, create a PR, and start the post-PR flow.
- `$glitchtip-pr`: from a GlitchTip issue, implement, create a PR, and perform an explicit verified Resolve.
- `$pr-health-monitor`: check the PR's CI, conflicts, body, and Codex/Copilot reviews, and start the observation-only watcher in XDG state.
- `$resume-pr-monitor`: re-check pending PR monitor events against fresh GitHub state and acknowledge only the follow-ups that succeeded.
- `$handle-pr-reviews`: handle unresolved review threads through fixing, replying, and resolving.
- `$deep-review` / `$lite-review`: review changes from multiple perspectives or from focused perspectives.
- `$issue-pr-deep` / `$issue-pr-lite`: create a PR from a GitHub Issue, depending on the size of the change.
- `$glitchtip-pr-deep` / `$glitchtip-pr-lite`: create a PR from a GlitchTip issue, depending on the size of the change.
- `$pr-cleanup`: clean up after a merged PR.
- `$wait-for-copilot-review` / `$wait-for-pr-close`: watch for a PR review or close as a durable event.
- `$check-container-status`: check the state of Docker Compose projects.
- `$agents-md-maintainer`: maintain the agent guidance in `AGENTS.md`.
- `$rtk`: refer to the RTK usage instructions.
- `$trilium`: run the Trilium integration procedure.
- `$i-have-adhd`: switch to output that puts actions first, with numbered steps and explicit progress, for readers with ADHD.
- If an updated skill does not appear in the list, restart Codex.
