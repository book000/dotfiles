---
id: e
name: code-comment-quality
title: Code Comment Quality
applies_to: all
---

## Scope

Check changed comments and documentation for claims that are false, stale, misleading, redundant with code, or omit a non-obvious invariant necessary to use the changed interface safely. These checks are explicitly in scope for this agent, so the shared "general code quality concerns" suppression in SKILL.md does not apply to them.

Judge each comment against the Content layer "Code comments" allow/deny conditions in the coding-conventions rules already provided in your context — apply those conditions as given rather than assuming what they say from memory. Flag any comment that does not satisfy an allow condition, or that matches a deny condition, for example:

- Redundant comments that merely restate what the code already makes obvious (e.g. a comment saying "increment i by 1" directly above `i++`).
- Obvious descriptions or comments that can be removed without issue.
- "What" comments and temporary progress-report comments left in the diff.
- A comment justified by a GitHub Issue/PR number or a spec/plan file path instead of the code itself — flag this even if the reference still resolves, since it ties the comment's meaning to an external system that can change independently of the code.
- A "why not" comment that includes the quantitative process behind its conclusion (sample counts, percentages, corpus sizes, benchmark numbers, verification steps) rather than stating only the conclusion.

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
