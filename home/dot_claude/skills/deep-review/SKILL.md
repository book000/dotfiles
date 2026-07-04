---
name: deep-review
description: Deep code review of a GitHub PR or the local working diff. Runs independent, scoped sub-agent reviews (CLAUDE.md adherence, bugs, git history, security incl. AI-PR risks, performance, silent failures, type design, tests), scores each finding 0-100 for confidence, reports only findings with score >= 50, and for the user's own PRs auto-fixes, commits, pushes, and updates the PR body.
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

### Step 4: Parallel perspective reviews

**Launch the following 9 independent sub-agents (general-purpose) in parallel.**

Pass each agent: the diff, the change summary, and the list of CLAUDE.md / rules paths.
Each agent returns findings as: *problem summary + evidence + file:line reference*.

**Instructions passed to every agent (false-positive suppression):**

Do NOT report the following:
- Pre-existing issues on lines not touched by this PR
- Issues that linters, type checkers, or CI already catch (formatting, import errors, type errors, etc.)
- Intentionally suppressed issues (lint-ignore comments, etc.)
- General code quality concerns (test coverage, documentation) unless explicitly required in CLAUDE.md or explicitly listed as a specific agent's scope below (e.g. Agent e's redundant/stale-comment checks)
- Functional changes that are clearly intentional given the broader context
- Anything asserted without a concrete `file:line` citation

**Agent scopes:**

- **Agent a (CLAUDE.md compliance)**: Read the CLAUDE.md and rules files. Flag violations of instructions that are explicitly stated there. Remember: CLAUDE.md is guidance for Claude writing code, so not every rule applies during review. Only flag what CLAUDE.md explicitly calls out.

- **Agent b (bugs / correctness)**: Shallow scan of the diff for large, obvious bugs. Avoid reading context beyond the changed lines. Skip nitpicks.

- **Agent c (git history / blame)**: Check `git blame` and `git log` for changed files. Report issues only when historical context reveals a problem that is not visible from the diff alone.

- **Agent d (past PR comments) [PR mode only]**: Find recently merged PRs that touched the same files (`gh pr list --state merged`). Check their review comments for concerns that may also apply here.

- **Agent e (code-comment quality)**: Read code comments and docstrings in changed files. These checks are explicitly in scope for this agent, so the shared "general code quality concerns" suppression above does not apply to them. Flag:
  - Cases where the implementation contradicts what a comment describes.
  - Redundant comments that merely restate what the code already makes obvious (e.g. a comment saying "increment i by 1" directly above `i++`).
  - Comments prone to becoming stale — descriptions of specific values, counts, enumerated lists, or implementation details duplicated from the code, which are likely to drift out of sync when the code changes.
  - Unnatural mid-sentence line breaks: a compound word, phrase, or clause split at a position that ignores its semantic boundary (e.g. breaking a Japanese compound word between its constituent characters rather than at a natural word boundary, or breaking immediately before the particle/predicate that a preceding phrase modifies).
    Flag these by default — only skip the flag when joining the lines would clearly produce a line dramatically longer than the other single-line comments already present in the same file (exact character counting is unreliable for mixed-script text, so judge by comparison to the file's own surrounding comment lines instead of a fixed number).
    This applies to comments in source files and to prose in Markdown instruction files (e.g. `SKILL.md`) alike.
  - Redundant multi-line padding: an explanation stretched across unnecessarily many lines (rough guideline: 3+ lines) through synonymous restatement or repeated qualifiers, where the same content could be stated in far fewer lines.
    Do not flag intentional multi-line structures where each line could be given its own distinct one-line label naming what sets it apart from the others (e.g. one line per distinct branch, argument, or condition) — that is enumeration, not padding, even if it spans many lines.
    Also do not flag structured/boilerplate blocks such as JSDoc `@param`/`@returns` tags or license headers.

  If the same redundant/stale-prone/line-break/padding pattern repeats many times in the diff, report it once with one or two representative `file:line` examples rather than listing every occurrence.

- **Agent f (security)**: Check for:
  - Missing input validation / sanitisation (XSS, SQL injection, etc.)
  - Authorisation checks missing or at the wrong layer
  - Hardcoded secrets, tokens, or API keys; sensitive data in logs
  - **AI-PR specific risks:**
    - Unvalidated external input interpolated into prompts (prompt injection)
    - GitHub tokens with over-broad scopes
    - Model output executed as shell commands without validation

- **Agent g (performance)**: Check for:
  - Unnecessary loops, duplicate queries (N+1), etc.
  - Impact on hot paths or background jobs
  - Synchronous operations that could easily be async

- **Agent h (error handling / silent failures)**: Check for:
  - Swallowed errors (empty catch blocks, `|| true`, etc.)
  - Inappropriate fallbacks that hide real failures
  - Loss of error information (discarded stack traces, etc.)

- **Agent i (type design / tests)**: Check for:
  - Type invariants not expressed correctly (null/undefined leaking into types, etc.)
  - Missing tests for new features or critical paths — only when CLAUDE.md explicitly requires tests

### Step 5: Confidence scoring

For each finding returned by Step 4, **launch a parallel Haiku sub-agent** to assign a confidence score.
Pass each agent: the issue description, the CLAUDE.md path list, and the relevant diff section.
Use the following rubric **verbatim**:

Score the issue on a scale of 0-100 based on your level of confidence that it is a real issue:

- **0**: Not confident at all. This is a false positive that doesn't stand up to light scrutiny, or is a pre-existing issue.
- **25**: Somewhat confident. This might be a real issue, but may also be a false positive. The agent wasn't able to verify that it's a real issue. If the issue is stylistic, it is one that was not explicitly called out in the relevant CLAUDE.md.
- **50**: Moderately confident. The agent was able to verify this is a real issue, but it might be a nitpick or not happen very often in practice. Relative to the rest of the PR, it's not very important.
- **75**: Highly confident. The agent double checked the issue, and verified that it is very likely it is a real issue that will be hit in practice. The existing approach in the PR is insufficient. The issue is very important and will directly impact the code's functionality, or it is an issue that is directly mentioned in the relevant CLAUDE.md.
- **100**: Absolutely certain. The agent double checked the issue, and confirmed that it is definitely a real issue, that will happen frequently in practice. The evidence directly confirms this.

For issues sourced from CLAUDE.md, double-check that the CLAUDE.md actually mentions that specific issue before scoring high.

Findings from an agent's explicitly listed scope (e.g. Agent e's redundant/stale-comment checks) are not "unscoped stylistic nitpicks" for the purpose of the 25-point band above — score them on the same real-world-impact basis as any other finding (how likely the comment is to mislead a future reader or drift from the code it describes).

Each agent must return the score in the format: `Score: <0-100>`
(The Stop hook extracts scores using this exact format.)

### Step 6: Score filtering

Discard all findings with score < 50. If no findings remain, report "No issues found" and stop.

### Step 7: Re-check eligibility (PR mode only)

Launch a Haiku sub-agent to repeat the Step 1 eligibility check. Abort if the PR is now ineligible.

### Step 8: PR author check (PR mode only)

Run `gh api user --jq '.login'` to get the current GitHub user login.
Then run `gh pr view <PR> --json author --jq '.author.login'` to get the PR author.

- Author matches the current user login, or is a bot created by the current user → proceed to Step 9 (autofix).
- Any other author (Renovate, dependabot, external contributors) → skip to Step 12 (report only).

### Step 9: Autofix (own PRs only)

Fix all findings with score ≥ 50. Do not commit yet — fix all issues first.

For each issue:
1. Read the affected file with the Read tool.
2. Apply the fix with the Edit tool.
3. Confirm the fix addresses the issue.

### Step 10: Commit (own PRs only)

Commit all fixes:

1. `git add` to stage all modified files.
2. Commit following Conventional Commits (description in Japanese per project CLAUDE.md):

```
fix: コードレビュー指摘事項を修正

- [list of fixed issues]

Co-Authored-By: Claude <noreply@anthropic.com>
```

3. `git push origin <branch>` (use SSH).

### Step 11: Update PR body (own PRs only)

Run `gh pr edit <PR> --body "..."` to note that review issues were automatically fixed.

### Step 12: Report results

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
