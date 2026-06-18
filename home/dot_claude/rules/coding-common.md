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
  - "**/*.zsh"
---

# Common Coding Rules

Rules that apply regardless of language.

## All Languages

- Insert a half-width space between Japanese and alphanumeric characters in comments and text
- If existing error messages in a file have emoji prefixes, unify emoji usage across all error messages in that file
  - Use a single emoji that matches the content of the error message
- Write concise comments: omit the self-evident, explain *why* not *what*, and never leave edit-history notes (e.g. "Deleted X") in code — history belongs in commit messages / PRs
