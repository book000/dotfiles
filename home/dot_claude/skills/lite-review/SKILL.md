---
name: lite-review
description: Lightweight code review of a GitHub PR or the local working diff. Runs a single sub-agent covering 4 fixed perspectives (CLAUDE.md compliance, bugs/correctness, code comment quality, security), scores findings 0-100, reports only score >= 50, and for the user's own PRs auto-fixes, commits, pushes, and updates the PR body.
argument-hint: "[PR number or URL | omit to review the local working diff]"
disable-model-invocation: false
effort: medium
---

# lite-review skill

Lightweight code review pipeline for changes too small to warrant the full
`deep-review` sweep. Reuses `deep-review`'s scoring, autofix, and reporting
logic verbatim; only Step 4 (perspective reviews) differs.

## Mode detection

Same as `deep-review`:

- **PR mode** (argument provided): extract PR number or URL, use `gh pr diff / view` to get the diff. Eligible for autofix.
- **Local diff mode** (no argument): compute base with `git merge-base origin/<current-branch> HEAD` and diff with `git diff <base>..HEAD` plus working-tree changes. Report only — no autofix or commit.

## Steps

Execute the following steps strictly in order. `lite-review`'s Steps 1-3
are identical to `deep-review`'s Steps 1-3; `lite-review`'s Steps 5-12
correspond to `deep-review`'s Steps 6-13 (see
`~/.claude/skills/deep-review/SKILL.md` for their exact text) — only
`lite-review`'s own Step 4 below replaces `deep-review`'s Steps 4-5
(project-specific reviewer discovery and per-reviewer parallel review).

### Step 1: Eligibility check (PR mode only)

Same as `deep-review` Step 1.

### Step 2: Collect CLAUDE.md / rules content

Same as `deep-review` Step 2.

### Step 3: Summarise changes

Same as `deep-review` Step 3.

### Step 4: Single-agent perspective review (4 fixed perspectives)

Unlike `deep-review`'s Step 5 (one sub-agent per reviewer file), launch a
**single** general-purpose sub-agent covering all 4 perspectives below in
one call:

1. Read `~/.claude/skills/deep-review/reviewers/a-claude-md-compliance.md`, `b-bugs-correctness.md`, `e-code-comment-quality.md`, and `f-security.md` directly (reuse their
   `## Scope` bodies verbatim — do not duplicate the text into this file).
2. Pass the sub-agent: the full diff, the change summary from Step 3, the
   CLAUDE.md/rules content from Step 2 (with the "already read, don't
   re-Read" instruction), the shared false-positive suppression
   instructions (identical text to `deep-review` SKILL.md's Step 5
   suppression block), and all 4 reviewers' `## Scope` bodies together,
   instructing it to check the diff against all 4 perspectives in a
   single pass and return findings tagged with which perspective(s) they
   belong to.

Each agent returns findings as: *problem summary + evidence + file:line reference*.

### Step 5: Confidence scoring (batched)

Same as `deep-review` Step 6: one Haiku sub-agent call for all findings,
same rubric, same `Finding <N>: Score: <0-100>` output format.

### Step 6: Score filtering

Same as `deep-review` Step 7.

### Step 7: Re-check eligibility (PR mode only)

Same as `deep-review` Step 8.

### Step 8: PR author check (PR mode only)

Same as `deep-review` Step 9.

### Step 9: Autofix (own PRs only)

Same as `deep-review` Step 10.

### Step 10: Commit (own PRs only)

Same as `deep-review` Step 11.

### Step 11: Update PR body (own PRs only)

Same as `deep-review` Step 12.

### Step 12: Report results

Same as `deep-review` Step 13, with every occurrence of the report heading
changed from `### Deep Review` to `### Lite Review` (this applies across
all of Step 13's report variants — autofixed-own-PR, non-own-PR, and
no-issues-found — not just one) and the "no issues found" line changed to:

```
### Lite Review

No issues found. Checked for CLAUDE.md compliance, bugs/correctness, code comment quality, and security.
```

Formatting rules are identical to `deep-review` Step 13 (full SHA +
`#L<line>` links, no emoji, `Score: <number>` per finding, cite both code
and CLAUDE.md rule).
