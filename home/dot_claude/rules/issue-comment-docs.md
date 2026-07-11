# GitHub Issue Comment Documentation Rules

Rules for posting spec/plan/investigation documents as GitHub Issue comments, for work tied to a GitHub Issue.

---

## When to Apply

Applies to Markdown documents created for the user to read or review as a deliverable, **when the work is tied to a GitHub Issue** (e.g. `issue-pr` execution, brainstorming conducted directly on a GitHub Issue):

- Investigation results
- Spec files (`docs/superpowers/specs/*.md`)
- Plan files (`docs/superpowers/plans/*.md`)
- Other standalone write-ups intended for the user, tied to that Issue

Does not apply to:

- Work not tied to a GitHub Issue (Jira-linked `ticket-pr` work, standalone investigations, pre-Issue discussions) — follow `rules/confluence.md` instead.
- Commit messages, PR bodies, code comments, or other routine Git/GitHub artifacts.

## Procedure

### Initial post

Create a new comment on the Issue and capture its comment ID from the returned URL. `--body-file` reads the body directly from disk, so it never costs extra tokens — do not pass the body as a string argument instead.

```bash
url=$(gh issue comment "<issue-number>" --repo "<owner>/<repo>" --body-file <path>)
comment_id=${url##*issuecomment-}
```

### Update

Spec and plan documents are each posted as their own, separate comment. When revising one of them, update it by its own comment ID — **do not use `--edit-last`**. `--edit-last` targets "the last comment posted by the current user" on the whole Issue; if spec and plan are posted in sequence (spec first, then plan), the plan comment becomes the last one — so later using `--edit-last` to revise the spec would silently overwrite the plan's comment instead of updating the spec's own comment.

```bash
gh api "repos/<owner>/<repo>/issues/comments/<comment_id>" -X PATCH -F body=@<path>
```

`-F body=@<path>` reads the body from the file directly, same token-free property as `--body-file`.

### Reporting

After posting or updating, report **the URL only** — do not paste the document body again in chat or in another comment (same policy as `rules/confluence.md`).

## Document Language

Confluence pages were viewed only by the user, so they followed the user's private language setting. GitHub Issue comments are **public**, and the target project's main language may differ from the user's private setting. Documents posted here must follow **the language specified by the target project's CLAUDE.md (or AGENTS.md, etc.)** — not the user's private language preference. Default to English only if the project specifies no language. Code blocks, commands, and identifiers stay in their original form regardless of the body language.

This matches the instruction `issue-pr` already gives when invoking `superpowers:brainstorming`/`superpowers:writing-plans` to write the spec/plan documents ("the language required by the target project's CLAUDE.md").

## Notes

- Verify no sensitive information (tokens, passwords, internal URLs, credentials) is included before posting — same check required before any Confluence/Jira post (see `rules/security.md`).
- If `gh issue comment` / `gh api` fails (auth, network, permission), report it to the user rather than silently continuing — a missing comment breaks the link between the Issue and its spec/plan.
