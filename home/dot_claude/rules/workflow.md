# Workflow Rules

Rules and checklists for the full development workflow.

---

## ADR-001: GitHub Issues as primary tracker

**Decision**: Use GitHub Issues (via `gh` CLI) as the primary issue tracker.  
**Alternatives considered**: Jira-only, GitHub Projects.  
**Rationale**: Closest to the code, minimal context-switching.  
**Exception**: Use Jira when the user explicitly requests it (MCP integration).

## ADR-002: PR reviews must be fully resolved before session end

**Decision**: The Stop hook blocks session end when unresolved review threads exist.  
**Rationale**: Unresolved threads silently block merge and create follow-up debt.  
**Escape**: `SKIP_REVIEW_CHECK=1` for genuine false positives only.

**Explicit decline handling**: If the user explicitly declines to address the Stop hook's unresolved-review-thread warning for a specific PR, run `bash ~/.claude/hooks/mark-review-declined.sh <PR_NUMBER>` before ending the turn. This suppresses re-warning for that PR within the current session only (it does not persist across sessions) and is distinct from the blanket `SKIP_REVIEW_CHECK=1` escape, which skips all checks every time.

## ADR-003: deep-review score ≥ 50 findings must be fixed before PR creation

**Decision**: `/deep-review` must pass (no score ≥ 50 findings) before creating a PR.  
**Rationale**: Catches correctness bugs, security issues, and CLAUDE.md violations early.  
**Implementation**: PostToolUse and Stop hooks enforce this automatically.

---

## Pre-work checklist

1. Understand the project structure.
2. Confirm the working branch is not a closed-PR branch.
3. Branch from the latest remote default branch.
4. Delete stale local branches.
5. Install dependencies if required by the project.

## Pre-commit checklist

1. Commit message follows Conventional Commits. Description language: project CLAUDE.md → otherwise Japanese.
2. No sensitive information (tokens, passwords, internal URLs).
3. No lint / format errors.
4. Change works as expected.

## Pre-PR checklist

1. User has requested PR creation.
2. No sensitive information.
3. No conflict risk.
4. Run `/deep-review` (local diff mode) — fix all score ≥ 50 findings.

## Post-PR checklist

Run `/pr-health-monitor <PR number>` to automate, or manually:

1. Verify no merge conflicts.
2. Update PR body with current state only (no history). Language follows project CLAUDE.md, otherwise Japanese.
3. `gh pr checks <PR number> --watch` — confirm CI passes.
4. Request Copilot review, wait (`/wait-for-copilot-review`).
5. Address review comments (`/handle-pr-reviews`).

---

## GitHub Issues

- Manage via `gh` CLI.

## Jira (when explicitly requested)

- Interact via MCP. Identify the space by project name; confirm with user if absent.
- Ticket titles and descriptions: Japanese. Set `contentFormat: "markdown"`, use real newlines (not `\n`).
- On implementation start: transition to "In Progress".
- On PR ready to merge: comment on ticket with PR URL, transition to "Resolved".
- Child tickets in Business (simplified) projects: use JQL `parent = <ISSUE_KEY>` — they are not in `subtasks`.
- **Never reference Jira on GitHub Issues or pull requests.**
