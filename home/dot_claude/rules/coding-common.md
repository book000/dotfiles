---
paths:
  - "**/*.ts"
  - "**/*.tsx"
  - "**/*.js"
  - "**/*.jsx"
  - "**/*.mjs"
  - "**/*.cjs"
  - "**/*.py"
  - "**/*.go"
  - "**/*.rs"
  - "**/*.java"
  - "**/*.kt"
  - "**/*.swift"
  - "**/*.c"
  - "**/*.cpp"
  - "**/*.cs"
  - "**/*.rb"
  - "**/*.php"
  - "**/*.sh"
  - "**/*.bash"
---

# Common Coding Rules

Rules that apply regardless of language.

## All Languages

- Insert a half-width space between Japanese and alphanumeric characters in comments and text
- If existing error messages in a file have emoji prefixes, unify emoji usage across all error messages in that file
  - Use a single emoji that matches the content of the error message
- Content layer — each artifact carries one distinct layer of information; do not duplicate a layer into another artifact:
  - **Code** expresses *how*: the implementation steps themselves. If a comment is needed to understand the code, make the code clearer first instead of adding narration.
  - **Code comments** express *why not*: do not add comments by default.
    - Allowed only for: the reasoning behind the implementation choice (why this approach and not a rejected alternative), non-obvious constraints from the spec, security/performance/compatibility caveats, or assumptions likely to break in the future.
    - Never add: comments that restate what the code already shows, comments that only repeat what a function/variable name already makes obvious, "what" comments (e.g. "initialize the value", "increment the counter"), or temporary progress-report comments.
    - Never add: a reference to a GitHub Issue/PR number or a spec/plan file path as the comment's justification — the tracker item can be renamed, closed, or deleted independently of the code, leaving the comment unverifiable.
    - When stating a why-not conclusion, keep only the conclusion itself — drop the quantitative process behind it (sample counts, percentages, corpus sizes, benchmark numbers, verification steps), since that detail goes stale independently of the code and cannot be re-verified later.
    - If a single sentence needs more than one line break to fit, shorten the sentence itself instead of adding another break point — a sentence that keeps needing new breaks should be split into shorter sentences, not wrapped further.
    - Before finishing a task, review the comments you added or changed and remove any that fall under the "Never add" rules above.
  - **Test code** expresses *what*: test/spec names and assertions state the behavior being verified, not the internal implementation steps.
  - **Commit messages** express *why*: the description/body explains the motivation/reasoning for the change. The diff itself already shows *what* changed — do not restate it.
- Never leave edit-history notes (e.g. "Deleted X") in code — history belongs in commit messages / PRs
