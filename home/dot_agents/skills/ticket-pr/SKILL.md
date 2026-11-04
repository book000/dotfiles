---
name: ticket-pr
description: Use to drive a Jira ticket end to end in Codex, from investigation through implementation, branch creation, PR creation, and starting the post-PR flow. For explicit `$ticket-pr` invocations only.
---

# Create a PR from a Jira ticket

A skill that takes a Jira ticket as its starting point and drives it end to end: requirement organization, branch creation, implementation, verification, commit, PR creation, and starting the post-PR flow.

## Usage

- Select `$ticket-pr` in Codex CLI and pass a Jira ticket key or URL
- Examples:
  - `$ticket-pr PROJECT-123`
  - `$ticket-pr https://company.atlassian.net/browse/PROJECT-123`

If a URL is passed, extract the ticket key from the end of the path.

## Prerequisites

- The Jira MCP (`mcp__atlassian__*`) is available
- `gh` is installed and authenticated
- Work in the current repository
- Leave decision records in Jira ticket comments, not in Markdown files

## Determining the branch type

Determine the branch type from the Jira issue type:

| Jira issue type | Branch type |
|---|---|
| Epic / Story / Task / New Feature / Improvement | `feat` |
| Bug | `fix` |
| Documentation | `docs` |
| Refactoring / Technical Debt | `refactor` |
| Sub-task | Follow the parent ticket; `feat` if unknown |

## Workflow

0. Resolve the cloudId.
   - If the argument is a URL (e.g. `https://company.atlassian.net/browse/PROJECT-123`): use the hostname (e.g. `company.atlassian.net`) as the `cloudId`
   - If it is only a ticket key: obtain the `cloudId` with `mcp__atlassian__getAccessibleAtlassianResources`
1. Fetch the Jira ticket information.
   - `mcp__atlassian__getJiraIssue({ cloudId: "<cloud-id>", issueIdOrKey: "<key>" })`
   - If the status is Done / Closed / Resolved or similar, show a warning and abort
2. Organize the requirements and uncertainties.
   - What will change
   - Expected risks
   - Unknowns
   - If external specifications are involved, always confirm via web search or primary sources
3. Make the pre-implementation decision.
   - If the ambiguity is high and proceeding would be dangerous, ask the user
   - Otherwise, state reasonable assumptions explicitly and proceed
4. Create the branch.
   - `git fetch --all --prune`
   - Prefer `origin/master` as the base, and use the default branch if it does not exist
   - Follow Conventional Branch for the branch name
   - **Important**: do not include the Jira ticket key in the branch name (the branch name is shown on the GitHub PR page)
   - Example: `feat/add-user-authentication`
5. Implement.
   - In dotfiles, update the chezmoi source under `home/`
   - Keep related documentation in sync
6. Verify.
   - At minimum, run the syntax / unit / integration tests corresponding to the change
   - For dotfiles, prioritize `tests/` and `chezmoi apply` checks
7. Commit and push.
   - Use Conventional Commits, and the language of the description follows the repository's language convention (`AGENTS.md` / `CLAUDE.md`, etc.); if there is none, ask the user (if non-interactive, leave the language undecided, defer, and report)
8. Create the PR.
   - Resolve the PR target repository with `gh-pr-target-repo.sh`
   - If an `upstream` remote exists, make it the default PR target
   - Resolve the reviewer with `gh-pr-reviewer.sh <owner/repo>`, and if book000 is output, specify it with `--reviewer` on `gh pr create` (do not specify one if the output is empty). If it exits non-zero, do not create the PR; stop and report
   - Create the PR as a draft (`gh pr create --draft`) when further edits to it are expected after creation, i.e. when any of the following is planned: a Copilot review whose comments will be addressed, review-thread handling via `$handle-pr-reviews`, or Jira follow-up commits. CI failures are not a reason for a draft: if CI fails after the PR is ready, return it to draft (`gh pr ready --undo`), fix, push, and re-evaluate. Create a regular PR only when none of these is planned or the user explicitly asks for a non-draft PR. An explicit user instruction always takes precedence
   - The ready decision is made by `$pr-health-monitor` / `$resume-pr-monitor`, not by this skill
   - The language of the PR body follows the repository's language convention (`AGENTS.md` / `CLAUDE.md`, etc.); if there is none, ask the user (if non-interactive, leave the language undecided, defer, and report). Describe only the latest state
   - Do not include a list of update history
   - **Important**: do not include the Jira ticket key or any mention of Jira in the PR title or body
9. Post a completion comment on the Jira ticket.
   - Post with `mcp__atlassian__addCommentToJiraIssue({ cloudId: "<cloud-id>", issueIdOrKey: "<key>", commentBody: "<completion message including the PR URL>" })`
10. Use `$pr-health-monitor` immediately after PR creation.
    - Example: `$pr-health-monitor 456`
    - After a restart, insufficient agent capacity, or a watcher stop, re-check and handle pending events with `$resume-pr-monitor <PR URL>`.

## Notes

- Codex CLI's official features do not add arbitrary custom slash commands like Claude Code. Command equivalents are replaced by skills.
- Do not drift to other work while waiting for review or CI. Run the post-PR flow to the end.
- Do not include mentions of Jira in GitHub Issues or PRs. Record them only on the Jira ticket side.
