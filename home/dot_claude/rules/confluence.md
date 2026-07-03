# Confluence Upload Rules

Rules for sharing user-facing Markdown deliverables via Confluence.

---

## When to Apply

Applies to Markdown documents created for the user to read or review as a deliverable:

- Investigation results
- Spec files (`docs/superpowers/specs/*.md`)
- Plan files (`docs/superpowers/plans/*.md`)
- Other standalone write-ups intended for the user, not for the codebase itself

Does not apply to commit messages, PR bodies, code comments, or other routine
Git/GitHub artifacts — only to documents whose primary purpose is to be read by the user.

## Procedure

1. **Resolve cloudId**: same approach as `ticket-pr`'s cloudId resolution — try the site
   hostname first, otherwise use `mcp__atlassian__getAccessibleAtlassianResources`.
2. **Determine space and parent page automatically — do not ask the user except in the fallback cases below.**
   - **Repository name source**: use `ISSUE_OWNER`/`ISSUE_REPO` as already resolved by the
     calling flow (`issue-pr`, `ticket-pr`, or the `rules/superpowers.md` spec/plan upload
     step) — the repository the Issue/ticket actually belongs to. Do not derive this from
     the local `git` `origin`/`upstream` remotes.
   - **Repository space search**: call `mcp__atlassian__getConfluenceSpaces` and look for a
     space whose `name` or `key` contains the repository name (e.g. `dotfiles`),
     case-insensitive substring match.
     - Exactly one match → use that space.
     - Zero matches → fall back to the fixed Main space (key: `Main`).
     - Multiple matches → prefer a space whose `name` or `key` exactly equals the
       repository name (e.g. `dotfiles`, not merely a substring match like
       `my-dotfiles`); if none is an exact match, sort the matches by space name and
       pick the first one. Do not ask the user to choose.
   - **Parent page**: always leave unset (upload at the space root). Do not attempt to
     auto-select a parent page and do not ask the user about it.
   - **Session cache**: once resolved for a repository in this session, reuse the same
     space for subsequent uploads targeting the same repository in that session.
   - **Fallback to asking**: if the calling flow has no `ISSUE_OWNER`/`ISSUE_REPO` context
     (e.g. a standalone document upload not tied to an Issue/ticket), or if the
     `mcp__atlassian__getConfluenceSpaces` call itself fails, report this to the user and
     ask how to proceed — do not guess or fabricate a space key or page ID in that case.
3. **Check for sensitive information**: verify the document contains no secrets (tokens,
   passwords, internal URLs, credentials) before uploading — same check already required
   before posting to GitHub Issues or Jira (see `rules/security.md`).
4. **Create the page** with `mcp__atlassian__createConfluencePage`:
   - `cloudId`, `spaceId`, `parentId` (if any), `title`, `body`, `contentFormat: "markdown"`.
   - Title convention: `<doc type> - <topic>`, e.g. `Investigation - <topic>`,
     `Spec - Issue #<number> <title>`, `Plan - Issue #<number> <title>`. Use whatever
     language the document itself is written in for `<topic>`/`<title>`; keep `<doc type>`
     in English so the title convention stated here stays consistent with this rule file.
5. **Update instead of duplicating**: if the document is revised later in the same session
   (e.g. after sub-agent review feedback or user comments), reuse the page created in step 4
   and call `mcp__atlassian__updateConfluencePage` with its `pageId` instead of creating a
   new page.
6. **Present the URL, not the content**: report the resulting Confluence page URL to the
   user. Do not paste the full document body again in chat or in an Issue/ticket comment —
   a short summary plus the Confluence URL is sufficient.

## Interaction with Other Skills

- **`issue-pr` / `ticket-pr`**: after uploading a deliverable document (spec/plan for
  `issue-pr`, the requirements document for `ticket-pr`) to Confluence, the GitHub Issue
  comment / Jira ticket comment must contain the Confluence URL plus a short summary only
  — not the full document body. Phase numbers are deliberately not pinned here since both
  skills renumber their own phases independently of this rule; see each skill's own
  SKILL.md for its current phase numbers (`ticket-pr`'s upload+comment step is its
  Phase 6 as of this writing).
- **`rules/superpowers.md` spec/plan review workflow**: after the sub-agent review is
  complete, upload the reviewed document to Confluence before presenting it to the user, and
  give the user the Confluence URL alongside the local file path.

## Notes

- If MCP resolution (cloudId, space, page) fails, report the error to the user and ask how
  to proceed rather than guessing.
- Uploaded content is still subject to `rules/security.md` — never include secrets.
