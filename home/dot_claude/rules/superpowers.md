# Superpowers Workflow Rules

## Spec and Plan Agent Review

After writing a spec file (`docs/superpowers/specs/*.md`) or a plan file
(`docs/superpowers/plans/*.md`), **before asking the user to review it**,
you MUST dispatch a sub-agent to review the document and apply fixes.

### Review procedure

1. Dispatch the review sub-agent with the file path to review: the
   `spec-reviewer` sub-agent (Agent tool, `subagent_type: spec-reviewer`)
   for a spec file (`docs/superpowers/specs/*.md`), or the `plan-reviewer`
   sub-agent (`subagent_type: plan-reviewer`) for a plan file
   (`docs/superpowers/plans/*.md`).
2. Wait for the sub-agent to complete.
3. If the sub-agent reports fixes, read the updated file and confirm the
   changes look correct.
4. If the sub-agent reports ambiguities, resolve them with the user via
   AskUserQuestion before proceeding.
5. Only after all issues are resolved, post or upload the document:
   - If the document is tied to a GitHub Issue (e.g. `issue-pr` execution,
     brainstorming conducted directly on a GitHub Issue), follow
     `rules/issue-comment-docs.md` and present the user with the local file
     path and the Issue comment URL.
   - Otherwise, follow `rules/confluence.md` and present the user with the
     local file path and the Confluence URL.

### Clarifying questions

**Main agent:** All clarifying questions directed at the user MUST be asked
via the AskUserQuestion tool. Do not ask questions as plain text.

**Sub-agents:** Sub-agents cannot use AskUserQuestion. If a sub-agent needs
to ask the user something, it must report the question (with options where
applicable) back to the main agent in its output. The main agent then uses
AskUserQuestion to relay it to the user.

## Local-Only Artifacts (`.gitignore` Compliance)

`docs/superpowers/` and `.superpowers/` are intentionally excluded via the
global `.gitignore` (`home/dot_config/git/ignore`). Spec and plan documents
under these paths are local-only working artifacts — after uploading them
to Confluence (per `rules/confluence.md`), do NOT force-add or commit them
to git (no `git add -f`, no `--force`). The durable record is the
Confluence page, not the git history.
