---
name: ticket-pr
description: Investigate a Jira ticket, implement a fix, and create a PR end-to-end. For explicit /ticket-pr invocations only.
argument-hint: "[Jira ticket key or URL, e.g. PROJECT-123]"
disable-model-invocation: true
---

# Create PR from Jira Ticket

This skill operates in two modes: **plan mode** and **execution mode**.

`$ARGUMENTS` receives a Jira ticket key (e.g. `PROJECT-123`) or URL (e.g. `https://company.atlassian.net/browse/PROJECT-123`).
If a URL is passed, extract the ticket key from the end of the path.

## Mode Detection

Detected by checking if the system-reminder contains "Plan mode is active" or "plan file" (case-insensitive partial match).
If present: plan mode. Otherwise: execution mode (fallback).

---

## Notes on Jira MCP Operations

The following applies to both modes.

- **Fetching child issues**: In Business (simplified) projects, child issues are created as the "Task" type
  rather than the "Sub-task" type, so they are not included in the parent ticket's `subtasks` field.
  To check or fetch child tickets, don't rely on `subtasks` — instead use
  `mcp__atlassian__searchJiraIssuesUsingJql` with the JQL `parent = <ISSUE_KEY>`
  (or `project = <KEY> AND parent = <ISSUE_KEY>` if needed).
- **Line breaks in comments/descriptions**: When posting comments or descriptions via
  `mcp__atlassian__addCommentToJiraIssue` etc., explicitly set `contentFormat: "markdown"`. Write line breaks as
  actual newline characters, not the literal `\n` (don't add extra escaping). This prevents
  doubled line breaks and literal `\n` from showing up in the rendered text.

---

## Plan Mode Workflow

### Phase 0: Resolve cloudId

Every Jira MCP tool call requires `cloudId`. Resolve it as follows:

1. If `$ARGUMENTS` is a URL (e.g. `https://company.atlassian.net/browse/PROJECT-123`):
   - Use the hostname (e.g. `company.atlassian.net`) as the `cloudId`
2. If only a ticket key is given (e.g. `PROJECT-123`):
   - Use `mcp__atlassian__getAccessibleAtlassianResources` to list available sites and identify the target `cloudId`

### Phase 1: Fetch Jira Ticket Info

Fetch ticket info with the MCP tool `mcp__atlassian__getJiraIssue`.

```
mcp__atlassian__getJiraIssue({
  cloudId: "<cloud-id>",
  issueIdOrKey: "<ticket-key>",
  fields: ["summary", "description", "issuetype", "status", "priority", "assignee", "comment"]
})
```

If the ticket status is Done / Closed / Resolved / etc., show a warning and stop processing.
To check for child tickets, use the JQL `parent = <ISSUE_KEY>` instead of the `subtasks` field
(see "Notes on Jira MCP Operations" for details).

### Phase 2: Analysis

1. Determine ticket type (feat / fix / docs / refactor)
   - Epic / Story / Task / New Feature / Improvement → `feat`
   - Bug → `fix`
   - Documentation → `docs`
   - Refactoring / Technical Debt → `refactor`
   - Sub-task → follow the parent ticket's type, `feat` if unknown
2. Files to change and impact scope
3. List of unknowns

### Phase 3: Ask the User

Use the AskUserQuestion tool only if there are unknowns.
Do not ask "Is this plan okay?" — that is ExitPlanMode's role.

AskUserQuestion limits: roughly 4-6 calls per session, each question times out after 60 seconds, and it cannot be used from sub-agents via the Task tool.

### Phase 4: Check External Specs

If external dependencies or latest specs are needed, check with WebSearch or official docs (Context7, etc.).
(Do not consult other agents.)

### Phase 5: Write the Requirements Document

Create in the following format:

```markdown
# <ticket-key> Requirements

## Overview
- **Ticket title**: [title]
- **Ticket key**: [PROJECT-123]
- **Ticket type**: Epic / Story / Task / Bug / ...
- **Branch type**: feat / fix / docs / refactor
- **Impact scope**: [files/modules]

## Requirements
### Functional Requirements
[detailed functional requirements]

### Non-Functional Requirements
- **Security**: [requirements]
- **Performance**: [requirements]

## Implementation Plan
### Key Steps
1. [step 1]
2. [step 2]

## Branch Name
`<type>/<description>`

## Decision Log
1. Summary of the decision
2. Alternatives considered
3. Rejected alternatives and reasons
4. Assumptions and uncertainties
5. Whether other agents can review
```

### Phase 6: Post Comment to Jira Ticket

Post the requirements document as a comment with the MCP tool `mcp__atlassian__addCommentToJiraIssue`.

```
mcp__atlassian__addCommentToJiraIssue({
  cloudId: "<cloud-id>",
  issueIdOrKey: "<ticket-key>",
  commentBody: "<requirements document content>",
  contentFormat: "markdown"
})
```

Always verify no sensitive information is included.
Explicitly set `contentFormat: "markdown"`, and write line breaks as actual newline
characters rather than the literal `\n` (see "Notes on Jira MCP Operations" for details).

### Phase 7: Write to Plan File

Write to the plan file path specified in the system-reminder using the Write tool.

### Phase 8: Run ExitPlanMode

```
ExitPlanMode()
```

---

## Execution Mode Workflow

### Prerequisites

- `gh` must be installed
- Must be run inside a Git repository

### Resolve cloudId

Every Jira MCP tool call requires `cloudId`. Resolve it as follows:

1. If `$ARGUMENTS` is a URL (e.g. `https://company.atlassian.net/browse/PROJECT-123`):
   - Use the hostname (e.g. `company.atlassian.net`) as the `cloudId`
2. If only a ticket key is given (e.g. `PROJECT-123`):
   - Use `mcp__atlassian__getAccessibleAtlassianResources` to list available sites and identify the target `cloudId`

### Fetch Jira Ticket Info

Fetch ticket info with the MCP tool `mcp__atlassian__getJiraIssue`.

```
mcp__atlassian__getJiraIssue({
  cloudId: "<cloud-id>",
  issueIdOrKey: "<ticket-key>",
  fields: ["summary", "description", "issuetype", "status", "priority", "assignee", "comment"]
})
```

If the ticket status is Done / Closed / Resolved / etc., show a warning and stop processing.

### Determine Branch Type

Determine the branch type from the Jira issue type:

| Jira Issue Type | Branch Type |
|---|---|
| Epic / Story / Task / New Feature / Improvement | `feat` |
| Bug | `fix` |
| Documentation | `docs` |
| Refactoring / Technical Debt | `refactor` |
| Sub-task | follow the parent ticket, `feat` if unknown |

### Create Branch

Prefer `origin/master`, falling back to the default branch if it doesn't exist:

```bash
git fetch --all --prune
git checkout -b <branch_name> origin/master
```

Branch name follows Conventional Branch (e.g. `feat/add-user-authentication`).
**Important**: do not include the Jira ticket key in the branch name. The branch name is
shown on the GitHub PR page, which would amount to referencing Jira there.

### Implement the Fix

Review the ticket content and implement appropriately.
In dotfiles, update chezmoi source files under `home/`.
Also update related documentation (README.md, CLAUDE.md, etc.).

### Verification

Run tests corresponding to the changes.
In dotfiles, prefer verifying with `chezmoi apply`.

### Commit

```bash
git add <files>
git commit -m "<type>: <Japanese description>"
```

Follow Conventional Commits, with `<description>` written in Japanese.

### Create PR

Resolve the target repository for the PR with `gh-pr-target-repo.sh`. If an `upstream` remote
exists, it is used as the default target.

```bash
REPO=$(gh-pr-target-repo.sh 2>/dev/null || echo "")
gh pr create ${REPO:+--repo "$REPO"} --title "<title>" --body "<PR body>"
```

**Important**: do not include the Jira ticket key or any reference to Jira in the PR title or body.
PR body: in Japanese, current state only, no update history.

Example PR body structure:
```markdown
## 概要

[変更の概要を日本語で記載]

## 変更内容

- [変更点 1]
- [変更点 2]

## 動作確認

- [確認項目 1]
- [確認項目 2]
```

### Completion Comment on Jira Ticket

After creating the PR, post a completion comment containing the PR URL with the MCP tool
`mcp__atlassian__addCommentToJiraIssue`.

```
mcp__atlassian__addCommentToJiraIssue({
  cloudId: "<cloud-id>",
  issueIdOrKey: "<ticket-key>",
  commentBody: "実装完了しました。PR を作成しました: <PR URL>",
  contentFormat: "markdown"
})
```

Explicitly set `contentFormat: "markdown"`, and write line breaks as actual newline
characters rather than the literal `\n` (see "Notes on Jira MCP Operations" for details).

### After PR Creation

Immediately run `/pr-health-monitor <PR number>` when done.

## Notes

- Do not drift to other tasks while waiting for review or CI
- Do not reference Jira in the PR body or GitHub Issues (record it only on the Jira ticket side)
- Record decision logs in Jira ticket comments
