---
name: trilium
description: Upload a local Markdown document to self-hosted Trilium via ETAPI, for documents not tied to a GitHub Issue.
disable-model-invocation: false
user-invocable: false
---

# Trilium Document Upload

Uploads a local Markdown document to the self-hosted Trilium Notes instance via its ETAPI,
for documents not tied to a GitHub Issue (`ticket-pr` requirements docs, standalone
investigations, spec/plan documents not posted as Issue comments).

## When to Apply

- Applies to: `ticket-pr` requirements documents, standalone investigations, spec/plan
  documents for work **not** tied to a GitHub Issue.
- Does not apply to: documents tied to a GitHub Issue — those follow
  `rules/issue-comment-docs.md` instead (posted directly as an Issue comment, no Trilium
  upload).

## Procedure

1. **Scope check**: confirm the document is not tied to a GitHub Issue (see "When to
   Apply" above). If it is, stop and follow `rules/issue-comment-docs.md` instead.
2. **Determine the slug**: the caller derives a deterministic slug from context, e.g.:
   - Spec not tied to an Issue: `spec-<topic-slug>`
   - Plan not tied to an Issue: `plan-<topic-slug>`
   - `ticket-pr` requirements document: `requirements-<jira-ticket-key>` (lowercased,
     symbols normalized to `-`)
   Reuse the same slug across revisions within the same session so re-uploads update the
   existing note instead of creating a duplicate.
3. **Sensitive information check**: before uploading, verify the document contains no
   secrets (tokens, passwords, internal URLs, credentials) — same standard as
   `rules/security.md`.
4. **Run the upload**: `bash ~/bin/trilium-upload.sh <file-path> <slug> <title>` and
   capture the share URL from its final line of stdout.
5. **On failure**: if the script exits non-zero, report the error verbatim to the user and
   ask how to proceed. There is no retry or fallback destination.
6. **Reporting**: after a successful upload, report only the share URL to the user — do
   not paste the document body again in chat or elsewhere.
