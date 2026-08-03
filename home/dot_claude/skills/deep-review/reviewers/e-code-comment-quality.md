---
id: e
name: code-comment-quality
title: Code-comment quality
applies_to: all
---

## Scope

Read code comments and docstrings in changed files. These checks are explicitly in scope for this agent, so the shared "general code quality concerns" suppression in SKILL.md does not apply to them.

Judge each comment against the Content layer "Code comments" allow/deny conditions in `~/.claude/rules/coding-common.md` — that file's content is already provided in your context, so apply those conditions as given rather than assuming what they say from memory. Flag any comment that does not satisfy an allow condition, or that matches a deny condition, for example:

- Redundant comments that merely restate what the code already makes obvious (e.g. a comment saying "increment i by 1" directly above `i++`).
- Obvious descriptions or comments that can be removed without issue.
- "What" comments and temporary progress-report comments left in the diff.
- A comment whose justification is a GitHub Issue/PR number or a spec/plan file path rather than the code itself — flag this regardless of whether the reference still resolves, since it makes the comment's meaning depend on an external system that can change independently of the code.
- A "why not" comment padded with the quantitative process behind its conclusion (sample counts, percentages, corpus sizes, benchmark numbers, verification steps) instead of stating only the conclusion.
- A comment sentence that needs more than one line break to fit — flag it as a signal that the sentence itself should be shortened (split into shorter sentences), not merely rewrapped. This is independent of the "line dramatically longer than surrounding comments" escape hatch used for the mid-sentence-break-placement check below — that escape hatch is about where a break falls, not about whether the sentence needed splitting in the first place.

Also flag the following mechanical defects, independent of the allow/deny judgment above — these are about a comment's accuracy or formatting, not about whether it should exist:

- Cases where the implementation contradicts what a comment describes.
- Comments prone to becoming stale — descriptions of specific values, counts, enumerated lists, or implementation details duplicated from the code, which are likely to drift out of sync when the code changes.
- Unnatural mid-sentence line breaks: a compound word, phrase, or clause split at a position that ignores its semantic boundary (e.g. breaking a Japanese compound word between its constituent characters rather than at a natural word boundary, or breaking immediately before the particle/predicate that a preceding phrase modifies).
  Flag these by default — only skip the flag when joining the lines would clearly produce a line dramatically longer than the other single-line comments already present in the same file (exact character counting is unreliable for mixed-script text, so judge by comparison to the file's own surrounding comment lines instead of a fixed number).
  This applies to comments in source files and to prose in Markdown instruction files (e.g. `SKILL.md`) alike.
- Redundant multi-line padding: an explanation stretched across unnecessarily many lines (rough guideline: 3+ lines) through synonymous restatement or repeated qualifiers, where the same content could be stated in far fewer lines.
  Do not flag intentional multi-line structures where each line could be given its own distinct one-line label naming what sets it apart from the others (e.g. one line per distinct branch, argument, or condition) — that is enumeration, not padding, even if it spans many lines.
  Also do not flag structured/boilerplate blocks such as JSDoc `@param`/`@returns` tags or license headers.

If the same redundant/stale-prone/line-break/padding pattern repeats many times in the diff, report it once with one or two representative `file:line` examples rather than listing every occurrence.
