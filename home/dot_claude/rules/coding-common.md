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
  - **Code comments** express *why not*: rejected alternatives, workarounds, non-obvious constraints. A comment that only restates what the next line already shows is a violation — delete it instead of writing it.
  - **Test code** expresses *what*: test/spec names and assertions state the behavior being verified, not the internal implementation steps.
  - **Commit messages** express *why*: the description/body explains the motivation/reasoning for the change. The diff itself already shows *what* changed — do not restate it.
- Never leave edit-history notes (e.g. "Deleted X") in code — history belongs in commit messages / PRs
