---
name: deep-review
description: Deep code review of a GitHub PR or the local working diff. Runs independent, scoped sub-agent reviews defined in reviewers/*.md and any project-specific reviewers, scores each finding 0-100 for confidence, reports only findings with score >= 50, and for the user's own PRs auto-fixes, commits, pushes, and updates the PR body.
argument-hint: "[PR number or URL | omit to review the local working diff]"
disable-model-invocation: false
effort: high
---

# deep-review skill

Self-contained code review pipeline — no external plugins. Reviews a GitHub PR or the local working diff using independent parallel sub-agents and confidence scoring.

## Mode detection

- **PR mode** (argument provided): extract PR number or URL, use `gh pr diff / view` to get the diff. Eligible for autofix.
- **Local diff mode** (no argument): compute base with `git merge-base origin/<current-branch> HEAD` and diff with `git diff <base>..HEAD` plus working-tree changes. Report only — no autofix or commit.

## Steps

Execute the following steps strictly in order.

### Step 1: Eligibility check (PR mode only)

Launch a Haiku sub-agent to verify the PR does not fall into any of these categories. Abort and report the reason if it does:

- Closed
- Auto-generated (Renovate, dependabot, etc.) or trivially simple
- The current GitHub user (run `gh api user --jq '.login'` to detect) has already posted a code-review comment

### Step 2: Collect CLAUDE.md / rules paths

Launch a Haiku sub-agent to collect and return the following paths:

- Root `CLAUDE.md` of the repository
- `CLAUDE.md` files in directories containing changed files
- All `*.md` files under `~/.claude/rules/`

### Step 3: Summarise changes

Launch a Haiku sub-agent to retrieve and return:

- **PR mode**: `gh pr view <PR> --json title,body,additions,deletions,files` and `gh pr diff <PR>`
- **Local diff mode**: `git diff <base>..HEAD --stat` and `git diff <base>..HEAD`

### Step 4: Explore project and consider project-specific reviewers

First, explore the project using the Explorer agent. If you already have a deep understanding of the project, skip this step.

Then, using the exploration results and the diff information, use a Haiku sub-agent to consider up to three project-specific review perspectives.

### Step 5: Parallel perspective reviews

**Load reviewer definitions, then launch one independent general-purpose sub-agent per loaded reviewer, all in parallel.**

1. Read every file under `~/.claude/skills/deep-review/reviewers/*.md` (the fixed reviewers, one file per perspective).
2. Filter by mode: in Local diff mode, exclude any reviewer file whose frontmatter `applies_to` is `pr-only`.
3. Each reviewer file uses this format:

   ```markdown
   ---
   id: <one-letter id, fixed reviewers only>
   name: <slug>
   title: <display title>
   applies_to: all | pr-only
   ---

   ## Scope

   <scope text, passed verbatim to the sub-agent>
   ```

   If `applies_to` is missing, empty, or not one of `all`/`pr-only`, treat it as `all`.

4. Pass each sub-agent: the diff, the change summary, the list of CLAUDE.md / rules paths, the shared false-positive suppression instructions below, and the `## Scope` body of its reviewer file.
Each agent returns findings as: *problem summary + evidence + file:line reference*.

**Instructions passed to every agent (false-positive suppression):**

Do NOT report the following:
- Pre-existing issues on lines not touched by this PR
- Issues that linters, type checkers, or CI already catch (formatting, import errors, type errors, etc.)
- Intentionally suppressed issues (lint-ignore comments, etc.)
- General code quality concerns (test coverage, documentation) unless explicitly required in CLAUDE.md or explicitly listed as a specific reviewer's scope (e.g. the `e-code-comment-quality.md` reviewer's redundant/stale-comment checks)
- Functional changes that are clearly intentional given the broader context
- Anything asserted without a concrete `file:line` citation

**Fixed reviewers:** see `~/.claude/skills/deep-review/reviewers/*.md` for the full list and scope of each.

### Step 6: Confidence scoring

For each finding returned by Step 5, **launch a parallel Haiku sub-agent** to assign a confidence score.
Pass each agent: the issue description, the CLAUDE.md path list, and the relevant diff section.
Use the following rubric **verbatim**:

Score the issue on a scale of 0-100 based on your level of confidence that it is a real issue:

- **0**: Not confident at all. This is a false positive that doesn't stand up to light scrutiny, or is a pre-existing issue.
- **25**: Somewhat confident. This might be a real issue, but may also be a false positive. The agent wasn't able to verify that it's a real issue. If the issue is stylistic, it is one that was not explicitly called out in the relevant CLAUDE.md.
- **50**: Moderately confident. The agent was able to verify this is a real issue, but it might be a nitpick or not happen very often in practice. Relative to the rest of the PR, it's not very important.
- **75**: Highly confident. The agent double checked the issue, and verified that it is very likely it is a real issue that will be hit in practice. The existing approach in the PR is insufficient. The issue is very important and will directly impact the code's functionality, or it is an issue that is directly mentioned in the relevant CLAUDE.md.
- **100**: Absolutely certain. The agent double checked the issue, and confirmed that it is definitely a real issue, that will happen frequently in practice. The evidence directly confirms this.

For issues sourced from CLAUDE.md, double-check that the CLAUDE.md actually mentions that specific issue before scoring high.

Findings from a reviewer's explicitly listed scope (e.g. the `e-code-comment-quality.md` reviewer's redundant/stale-comment checks) are not "unscoped stylistic nitpicks" for the purpose of the 25-point band above — score them on the same real-world-impact basis as any other finding (how likely the comment is to mislead a future reader or drift from the code it describes).

Each agent must return the score in the format: `Score: <0-100>`
(The Stop hook extracts scores using this exact format.)

### Step 7: Score filtering

Discard all findings with score < 50. If no findings remain, report "No issues found" and stop.

### Step 8: Re-check eligibility (PR mode only)

Launch a Haiku sub-agent to repeat the Step 1 eligibility check. Abort if the PR is now ineligible.

### Step 9: PR author check (PR mode only)

Run `gh api user --jq '.login'` to get the current GitHub user login.
Then run `gh pr view <PR> --json author --jq '.author.login'` to get the PR author.

- Author matches the current user login, or is a bot created by the current user → proceed to Step 10 (autofix).
- Any other author (Renovate, dependabot, external contributors) → skip to Step 13 (report only).

### Step 10: Autofix (own PRs only)

Fix all findings with score ≥ 50. Do not commit yet — fix all issues first.

For each issue:
1. Read the affected file with the Read tool.
2. Apply the fix with the Edit tool.
3. Confirm the fix addresses the issue.

### Step 11: Commit (own PRs only)

Commit all fixes:

1. `git add` to stage all modified files.
2. Commit following Conventional Commits.

```
fix: コードレビュー指摘事項を修正

- [list of fixed issues]

Co-Authored-By: Claude <noreply@anthropic.com>
```

3. `git push origin <branch>` (use SSH).

### Step 12: Update PR body (own PRs only)

Run `gh pr edit <PR> --body "..."` to note that review issues were automatically fixed.

### Step 13: Report results

- **PR mode**: post with `gh pr comment <PR> --body "..."`.
- **Local diff mode**: present results directly to the user.

#### Output format

When issues were found and autofixed:

```
### Deep Review

Found X issues and **automatically fixed them** in commit [sha]:

1. <brief issue description>

Score: <score>

<https://github.com/<owner>/<repo>/blob/<full_sha>/<path>#L<start>-L<end>>

**Fixed**: <description of the fix applied>
```

When issues were found (other author's PR, no autofix):

```
### Deep Review

Found X issues:

1. <brief issue description>

Score: <score>

<https://github.com/<owner>/<repo>/blob/<full_sha>/<path>#L<start>-L<end>>
```

When no issues were found:

```
### Deep Review

No issues found. Checked for bugs, CLAUDE.md compliance, security (incl. AI-PR risks), performance, error handling, silent failures, type design, and test coverage.
```

#### Formatting rules

- GitHub code links must use the full SHA + `#L<line>` format. Do not embed `$(git rev-parse HEAD)` — it will not expand in Markdown.
- No emoji.
- Each finding must include `Score: <number>` (the Stop hook extracts scores using this exact format).
- Cite both the code (`file:line`) and the relevant CLAUDE.md rule for each finding.
