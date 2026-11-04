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

AskUserQuestion cannot be used from sub-agents; if a sub-agent hits a real question, it reports it back and the main agent asks.

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

### Phase 6: Upload to Trilium and Post Comment to Jira Ticket

Invoke the `trilium` skill (via the Skill tool) to upload the requirements document.
Pass the file path, docType `spec`, topic = the lowercased ticket key (e.g. `proj-123`),
noteId = `spec_` plus the lowercased ticket key with `-` replaced by `_` (e.g.
`spec_proj_123`), and title `<ticket-key> Requirements`. These satisfy the skill's
constraints (noteId `^[a-zA-Z0-9_]{4,32}$`, topic `^[a-zA-Z0-9_-]{1,25}$`) for the usual
`<PROJECT>-<number>` key. The skill's pre-upload confirmation applies, so ask the user
before the upload unless they already explicitly asked for it. Capture the returned
share URL.

Then post a short summary plus the share URL as the ticket comment — not the full
document body — with the MCP tool `mcp__atlassian__addCommentToJiraIssue`.

```
mcp__atlassian__addCommentToJiraIssue({
  cloudId: "<cloud-id>",
  issueIdOrKey: "<ticket-key>",
  commentBody: "<short summary>[newline][newline]Details: <share URL>",
  contentFormat: "markdown"
})
```

`[newline]` above denotes an actual newline character, not the literal `\n` — see the
line-break note below.

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

Branch from the latest remote default branch:

```bash
git fetch --all --prune
git remote set-head origin -a >/dev/null 2>&1 || true
git checkout -b <branch_name> origin/HEAD
```

If the checkout still fails, stop and report instead of branching from another base.

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
git commit -m "<type>: <description>"
```

Follow Conventional Commits. `<description>` language: follow the target repository's language convention (check the root `AGENTS.md`, then `CLAUDE.md`; see the `Language` section of `~/.claude/CLAUDE.md`). If there is none, ask the user; in a non-interactive run, defer the commit and report the language as undetermined.

### Create PR

Resolve the target repository for the PR with `gh-pr-target-repo.sh`. If an `upstream` remote
exists, it is used as the default target.

Create the PR as a draft (`gh pr create --draft`) when further edits to it are expected after creation, i.e. when any of the following is planned: a Copilot review whose comments will be addressed, review-thread handling by `/pr-health-monitor`, or Jira/GlitchTip follow-up commits. CI failures are not a reason for a draft: if CI fails after the PR is ready, return it to draft (`gh pr ready --undo`), fix, push, and re-evaluate. Create a regular PR only when none of these is planned or the user explicitly asks for a non-draft PR. An explicit user instruction always takes precedence.

Set `DRAFT=1` when the PR is to be a draft (leave it empty otherwise) and pass `${DRAFT:+--draft}` to `gh pr create`. The ready decision is made later by `/pr-health-monitor`, not by this skill.

book000 is requested as the PR reviewer via `gh-pr-reviewer.sh` (empty output means skip the
`--reviewer` flag). If the helper exits non-zero, stop before creating the PR and report the failure.

```bash
REPO=$(gh-pr-target-repo.sh 2>/dev/null || echo "")
REVIEWER=${REPO:+$(gh-pr-reviewer.sh "$REPO")}
DRAFT=1  # set to empty for a regular (non-draft) PR
gh pr create ${REPO:+--repo "$REPO"} ${DRAFT:+--draft} ${REVIEWER:+--reviewer "$REVIEWER"} --title "<title>" --body "<PR body>"
```

**Important**: do not include the Jira ticket key or any reference to Jira in the PR title or body.
PR body: follow the target repository's language convention (same rule as the commit description; ask the user if there is none, defer if non-interactive). Current state only, no update history.

Example PR body structure (section headings in the repository's language; Japanese shown only as an example):
```markdown
## 概要

[summary of changes]

## 変更内容

- [change 1]
- [change 2]

## 動作確認

- [verification step 1]
- [verification step 2]
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

### Write Session State

After PR creation, write the PR URL to the session state file so hooks can reference it
without parsing the transcript:

```bash
mkdir -p ~/.claude/data && chmod 700 ~/.claude/data
PR_URL=$(gh pr view ${REPO:+--repo "$REPO"} --json url -q .url)
if [ -z "$PR_URL" ]; then
  echo "ERROR: gh pr view returned an empty URL, not writing session-state.json" >&2
  exit 1
fi
if ! jq -n --arg pr_url "$PR_URL" --arg session_id "${CLAUDE_CODE_SESSION_ID:-}" --argjson timestamp "$(date +%s)" \
    '{"pr_url": $pr_url, "session_id": $session_id, "timestamp": $timestamp}' \
    > ~/.claude/data/session-state.json; then
  echo "ERROR: failed to write session-state.json" >&2
  exit 1
fi
chmod 600 ~/.claude/data/session-state.json
```

If `PR_URL` comes back empty or the `jq` write fails, stop and report it
instead of leaving a stale/empty state file — hooks read this file without
parsing the transcript, so a silently broken write here breaks them too.

### After PR Creation

Immediately run `/pr-health-monitor "$PR_URL"` when done (the full URL from above, so the PR's repository is not re-resolved). Its unified Monitor handles review feedback, CI, conflicts and PR close (`/pr-cleanup`) in this conversation; the flow is complete once the Monitor is running.

## Notes

- Do not drift to other tasks while waiting for review or CI
- Do not reference Jira in the PR body or GitHub Issues (record it only on the Jira ticket side)
- Record decision logs in Jira ticket comments
