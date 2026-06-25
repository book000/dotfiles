## Guardrails / Rules

- Do not make unauthorized changes (disabling hooks, closing PRs, changing settings, etc.) without explicit user approval. If something is blocking progress, ask the user instead of silently working around it.
- Even for large-scale research or refactoring, do not cut corners — work carefully, methodically, and thoroughly. This is a mandatory requirement that applies in all cases.
- **Do not merge PRs until explicitly instructed.**

## Behavior

- Do not flatter me. Always engage with critical thinking; push back if you think I'm wrong.
- Skip phrases like "Great suggestion!" or "You're absolutely right!" — get to the point concisely.

## Language

- Final responses to the user must be in Japanese. For intermediate steps, use English except for key/important points, to reduce context size.
- Code comments: follow the project CLAUDE.md if it specifies one; otherwise Japanese. Error messages should be in English as a general rule.
- Insert a half-width space between Japanese and alphanumeric characters.
- **All Markdown files under `~/.claude/` must be written in English** (CLAUDE.md, skills, rules, etc.).

## Environment Rules

- Git commits must follow [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/). The `<description>` language: follow the project CLAUDE.md if it specifies one; otherwise Japanese.
- Branches must follow [Conventional Branch](https://conventional-branch.github.io). Use short-form `<type>` (feat, fix).
- When researching a GitHub repository, clone it to a temporary directory and search there.
- Keep CLAUDE.md up to date.
- Do not add commits or updates to existing Renovate-created PRs.
- For background monitoring, when monitoring ends or on error, send a message to the tmux session running Claude Code via send-keys so Claude Code can act automatically. Get the session name with `tmux display-message -p '#{session_name}'`. Example: `tmux send-keys -t "$SESSION" "message" && sleep 3 && tmux send-keys -t "$SESSION" Enter`. Without `sleep 3` between the message and Enter, Enter is sent before Claude Code recognizes the input and is treated as a newline.
- In `<<'EOF'` heredocs (single-quote delimiter), `\` does not function as an escape character, so backticks (`` ` ``) must be written as `` ` `` directly, not as `` \` ``. Writing `` \` `` outputs two characters and renders with a backslash in GitHub Markdown.

## Git Operations

Always use **SSH** (not HTTPS) for git push. Do not ask the user to fix git authentication manually. Handle it autonomously.

If the environment variables GH_CONFIG_DIR, GIT_AUTHOR_NAME, GIT_AUTHOR_EMAIL, GIT_COMMITTER_NAME, GIT_COMMITTER_EMAIL, or GIT_SSH_COMMAND are set, they must not be modified without permission.  
If you do not have access to the target repository, do not make assumptions; ask the user how to proceed.

Furthermore, you must not use the git config command to change the username or email address.

## PR / Issue Workflow

Use the following skills to run the workflow:

| Skill | Purpose |
|---|---|
| `/issue-pr <issue number>` | From issue to implementation and PR creation |
| `/ticket-pr <ticket key OR URL>` | From Jira ticket to implementation and PR creation |
| `/pr-health-monitor <PR number>` | Post-PR monitoring, CI, and review handling |
| `/handle-pr-reviews <PR URL>` | Reply to and resolve review threads |
| `/wait-for-copilot-review <PR number>` | Background wait for Copilot review |

See each skill (`/handle-pr-reviews`, `/pr-health-monitor`) for detailed steps and GraphQL queries.

## Issue / Ticket management

- As a general rule, use GitHub Issues for issues and tickets. GitHub Issues should be managed using the gh command
- If a user explicitly requests the use of Jira, interact with Jira via MCP
- Search for and identify the Jira space by the project name. If the relevant space does not exist, confirm with the user
- Jira ticket titles and descriptions must be written in Japanese. When posting, set `contentFormat: "markdown"` and write line breaks as actual newline characters (not the literal `\n`) to avoid line-break issues
- When starting implementation, please change the Jira ticket status to "In Progress". Once the PR is created, there are no conflicts, CI has passed, Copilot Review is complete, and the PR is ready to be merged, please comment to that effect on the ticket and change the status to "Resolved".
- When checking content or changing status, please also consider the child tickets. In Business (simplified) projects, child issues are created as the "Task" type and are not listed in the parent's `subtasks` field — use the JQL `parent = <ISSUE_KEY>` to fetch them (see the ticket-pr skill for details).
- Do not mention Jira on GitHub Issues or pull requests

## Must Do

Use the Todo tool to track all of the following without omission.

### Before New Work

1. Thoroughly explore and understand the project
2. Verify the working branch is appropriate — not a branch with a closed PR
3. Verify it is a new branch based on the latest remote branch
4. Verify that closed/unnecessary branches have been deleted
5. Install dependencies using the project's specified package manager

### Before Commit/Push

1. Commit message follows [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/). `<description>` language: follow the project CLAUDE.md if specified; otherwise Japanese.
2. No sensitive information in the commit
3. No Lint / Format errors
4. Verify the change works as expected

### Before Creating a PR

1. Confirm the user has requested a PR
2. No sensitive information in the commit
3. No risk of conflicts
4. Run `/deep-review` (local diff mode — no argument) and **address all findings with score ≥ 50** before proceeding to PR creation

### After Creating a PR

Run `/pr-health-monitor <PR number>` to automate, or do the following manually:

1. Verify no conflicts
2. Update PR body with current state only (no history). Language: follow the project CLAUDE.md if it specifies one; otherwise Japanese
3. Confirm CI with `gh pr checks <PR number> --watch`
4. Request Copilot review and wait (`/wait-for-copilot-review`)
5. Address review comments (`/handle-pr-reviews`)

@CLAUDE.local.md

@RTK.md
