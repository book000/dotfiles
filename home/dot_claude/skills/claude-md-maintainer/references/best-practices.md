# CLAUDE.md Best Practices

A static reference used by the `claude-md-maintainer` skill as the baseline for assessing drift and deciding whether to rewrite or append to a CLAUDE.md.

## Categories to cover

A good CLAUDE.md covers the following categories, without gaps or excess. Categories that don't apply to the project (e.g. a "test commands" category for a project with no tests) may be omitted rather than force-filled.

1. **Purpose / project overview**: what the project does and its main features, in about 2-5 lines.
2. **Development commands**: build, test, lint, format, run commands, etc. Do not list commands that don't exist (e.g. writing `npm test` when there is no `package.json`).
3. **Architecture / key files**: the meaning of the directory layout, main entry points, and the location of important config files.
4. **Coding conventions**: recommended vs. discouraged patterns, with concrete examples. Avoid abstract instructions like "write good code."
5. **Testing approach**: how to run tests; if there are no tests, say so and note an alternative verification method (e.g. manual verification steps).
6. **Documentation update rules**: which changes require updating which docs (README, CLAUDE.md itself, etc.).
7. **Repository-specific operating rules**: how secrets are managed, external service integrations, team-specific prohibitions, etc.
8. **Security / prohibitions**: rules whose violation causes serious problems, such as never committing secrets in plaintext.

## How to write a good CLAUDE.md

- **Be concrete**: instead of "handle errors appropriately," write a verifiable, concrete rule such as "return errors as `Result<T, E>`; never use `panic!`."
- **List only commands/files that actually exist**: references to nonexistent commands or removed files induce incorrect behavior at execution time.
- **Be concise**: omit redundant explanations and obvious content (e.g. "Git is a version control system"). Focus on points where the agent actually gets confused or makes mistakes.
- **Pair recommended/discouraged**: presenting "Recommended: X" / "Discouraged: Y" side by side makes it easier for the agent to decide.
- **Assume staleness and document the update path**: in the "documentation update rules" section, spell out which kinds of changes require updating CLAUDE.md itself.
- **Layer where applicable**: in monorepos, put overall policy in the root CLAUDE.md and directory-specific matters in subdirectory CLAUDE.md files (only where applicable).
- **Organize with headings**: use `##`/`###` headings to group by category rather than a flat list of bullets, so the agent can skim only the sections it needs.

## Anti-patterns (writing styles to avoid)

- **Leaving TODO/TBD in place**: don't ship with unresolved placeholder items.
- **Overly abstract instructions**: instructions that can't be turned into concrete action, like "write good code" or "follow best practices."
- **Contradictory descriptions**: don't state different rules for the same subject in multiple places.
- **Unstructured appending to one giant file**: continuously appending chronologically while ignoring categories destroys structure for later readers.
- **Pasting raw implementation details**: don't just paste code; explain "why" and "what must be preserved."
- **Leaving stale information**: descriptions that no longer track changes to the repository structure or commands.

## Good example / bad example

**Bad example:**

> This project is very complex, so be careful when making changes. Write good code, and write tests too.

**Good example:**

> ## Development commands
> - `npm test`: run unit tests with Jest.
> - `npm run lint`: check with ESLint. Also runs in CI.
>
> ## Coding conventions
> - Recommended: use `async/await` for asynchronous code.
> - Discouraged: adding new `.then()` chains (for consistency with existing code).
