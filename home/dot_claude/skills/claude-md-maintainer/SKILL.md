---
name: claude-md-maintainer
description: Analyze a project's CLAUDE.md against curated best practices plus a live web-search delta, then either rewrite it wholesale or apply targeted edits depending on how far it has drifted. Also creates a CLAUDE.md from scratch when none exists.
argument-hint: "[directory | omit to use the current directory]"
disable-model-invocation: false
---

# claude-md-maintainer skill

Analyzes a project's `CLAUDE.md` against a static best-practices reference (`references/best-practices.md`) plus a live web-search delta on current trends, then either rewrites it wholesale or applies targeted edits depending on how far the existing content has drifted. If no `CLAUDE.md` exists, creates one from scratch.

## Determine the target directory

If an argument is given, use that directory as the target. Otherwise, use the current directory.

```bash
TARGET_DIR="${1:-.}"
if [ ! -d "$TARGET_DIR" ]; then
  echo "ERROR: directory not found: $TARGET_DIR" >&2
  exit 1
fi
if [ ! -r "$TARGET_DIR" ]; then
  echo "ERROR: directory not readable: $TARGET_DIR" >&2
  exit 1
fi
```

If the target directory does not exist or is not readable, report the error and abort.

## Step 1: Explore the target project

- Check whether `$TARGET_DIR/CLAUDE.md` exists; if so, `Read` it in full.
- Determine the project's language/framework from the presence of `package.json` / `pyproject.toml` / `Cargo.toml` / `go.mod` etc.
- Understand the directory layout, README, and existing test/lint commands (e.g. `package.json`'s `scripts`).
- Check whether the directory is under git:

```bash
cd "$TARGET_DIR" && git rev-parse --is-inside-work-tree >/dev/null 2>&1
```

If not under git, record a warning that post-hoc diff review won't be possible, and continue (the write itself still happens).

## Step 2: Load the static reference

`Read` `~/.claude/skills/claude-md-maintainer/references/best-practices.md`.

## Step 3: Live search for current trends

Run WebSearch with queries such as the following, and extract only the **delta** against `references/best-practices.md` (newly emerged recommendations, deprecated conventions, updates to official docs):

- `CLAUDE.md best practices <current year>`
- `Claude Code memory files guide`
- `Anthropic Claude Code CLAUDE.md documentation`

If a search result looks promising, use WebFetch to retrieve the page in detail.

If the search fails (network error, etc.), continue Step 4 onward using only the static reference, and note this in the final report (Step 6).

Only fold a delta item into the final `CLAUDE.md` if it is directly actionable for this specific project (e.g. a size/structure limit that the project actually risks hitting, a documented anti-pattern the project currently exhibits). Do not pad the output with generic advice that doesn't change what gets written for this project — the goal is a concise, project-specific document, not a copy of the search results.

## Step 4: Extract project-specific information

From the existing `CLAUDE.md` (if any), extract project-specific information that must not be lost:

- Concrete commands (build, test, deploy, etc.)
- Known pitfalls and caveats
- Facts about the repository structure
- Team-specific operating rules

Cross-check these against Step 1's exploration results, and verify whether the existing description has drifted from reality (e.g. whether a referenced command actually exists in `package.json`). Record any drifted descriptions (references to nonexistent commands, etc.) as input for Step 5's decision.

If no `CLAUDE.md` exists yet, there is nothing to extract here — treat this step as a no-op and rely solely on Step 1's exploration results as the factual basis for Step 6.

## Step 5: Assess drift and decide the update approach

Using the results of Steps 2-4, assess how far the existing `CLAUDE.md` has drifted from the best practices.

- **Large drift** (any of the following applies) → rewrite wholesale.
  - Half or more of the applicable categories in `references/best-practices.md`'s "Categories to cover" (excluding categories that don't apply to the project's nature) are missing.
  - The heading structure is broken and not organized by category.
  - There are multiple descriptions that have drifted from reality (references to nonexistent commands, removed files, etc.).
- **Small drift** (applicable categories are largely present and partial additions/corrections suffice) → edit only the affected sections.
- No existing `CLAUDE.md` → create from scratch (treated the same as a wholesale rewrite).

Record the decision (wholesale rewrite / partial edit / new creation) and its rationale.

## Step 6: Apply changes and report

Write `CLAUDE.md` in English as a rule. Only deviate from English when the existing `CLAUDE.md` (for a partial edit) is written in another language — in that case, keep that language for consistency rather than switching mid-document. This rule governs the language of the `CLAUDE.md` body itself; it is independent of whatever language you use to talk to the user in this conversation.

Following Step 5's decision, rewrite `$TARGET_DIR/CLAUDE.md` with `Write` (for a wholesale rewrite or new creation) or `Edit` (for a partial edit).

If the write fails (e.g. insufficient permissions), report the error and abort.

After the write, report the following to the user:

- Whether a wholesale rewrite, partial edit, or new creation was performed, and the rationale.
- A summary of the main changes.
- If the target directory is under git: note that `git diff` (for an edited existing file) or `git status` (for a newly created file) can be used to review the details.
- If Step 3's live search failed, note that.
- If the target directory was not under git, note that (the warning recorded in Step 1).
