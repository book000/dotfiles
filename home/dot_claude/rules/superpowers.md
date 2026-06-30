# Superpowers Workflow Rules

## Spec and Plan Agent Review

After writing a spec file (`docs/superpowers/specs/*.md`) or a plan file
(`docs/superpowers/plans/*.md`), **before asking the user to review it**,
you MUST dispatch a sub-agent to review the document and apply fixes.

### Review procedure

1. Dispatch a sub-agent with the following instruction (substituting the
   actual file path):

   > Read `<file path>`. Review it for: placeholder text (TBD/TODO),
   > internal contradictions, ambiguous requirements that could be
   > interpreted two ways, missing coverage relative to the stated goal,
   > and — for plan files only — steps that describe what to do without
   > showing how (missing code blocks). Fix all issues you find in place.
   > Report a one-line summary of each fix made, or "No issues found."

2. Wait for the sub-agent to complete.
3. If the sub-agent reports fixes, read the updated file and confirm the
   changes look correct before proceeding.
4. Only after the review is complete, present the file to the user for
   review.

### Clarifying questions

All clarifying questions directed at the user MUST be asked via the
AskUserQuestion tool. Do not ask questions as plain text.
