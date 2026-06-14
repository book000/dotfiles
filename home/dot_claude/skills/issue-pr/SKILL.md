---
name: issue-pr
description: Investigate a GitHub Issue, implement a fix, and create a PR end-to-end. For explicit /issue-pr invocations only.
argument-hint: "[Issue number or URL]"
disable-model-invocation: true
---

# Create PR from Issue

This skill operates in two modes: **plan mode** and **execution mode**.

## Mode Detection

Detected by checking if the system-reminder contains "Plan mode is active" or "plan file".
If present: plan mode. Otherwise: execution mode.

---

## Plan Mode Workflow

### Phase 1: Analyze the Issue

```bash
gh issue view $ARGUMENTS --json title,state,body,comments,author
```

Analyze:
1. Issue type (feat/fix/docs/refactor)
2. Files to change and impact scope
3. List of unknowns

### Phase 2: Ask the User

Use the AskUserQuestion tool to clarify unknowns.
Do not ask "Is this plan okay?" — that is ExitPlanMode's role.

### Phase 3: Check External Specs

If external dependencies or latest specs are needed, check with WebSearch or official docs (Context7, etc.).
(Do not consult other agents.)

### Phase 4: Write the Requirements Document

Create in the following format:

```markdown
# Issue #<number> Requirements

## Overview
- **Issue title**: [title]
- **Issue number**: #[number]
- **Issue type**: feat/fix/docs/refactor
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

### Phase 5: Post Comment to Issue

```bash
gh issue comment $ARGUMENTS --body "$(cat <<'EOF'
[requirements document content]
EOF
)"
```

Always verify no sensitive information is included.

### Phase 6: Write to Plan File

Write to the plan file path specified in the system-reminder using the Write tool.

### Phase 7: Run ExitPlanMode

```
ExitPlanMode()
```

---

## Execution Mode Workflow

### Prerequisites

- `gh` and `jq` must be available
- Must be run inside a Git repository

### Fetch Issue Info

```bash
gh issue view $ARGUMENTS --json title,state,body,comments,author
```

If the issue is not OPEN, display a warning.

### Create Branch

```bash
git fetch origin
# Check default branch
git checkout -b <branch_name> origin/<default_branch>
```

Branch name follows Conventional Branch (feat/fix/docs/refactor).

### Implement the Fix

Review the issue content and implement appropriately.
In dotfiles, update chezmoi source files under `home/`.

### Create PR

```bash
gh pr create --title "<title>" --body "<PR body>"
```

PR body: follow the project CLAUDE.md language if specified; otherwise Japanese. Current state only, no update history.

### After PR Creation

Immediately run `/pr-health-monitor <PR number>` when done.

## Notes

- Do not drift to other tasks while waiting for review or CI
- Record decision log in the issue comment or PR body (not in Markdown files)
