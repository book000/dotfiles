# Security Rules

Security guardrails enforced across all projects.

---

## Secrets and credentials

- Never commit API keys, tokens, passwords, or internal URLs.
- Store secrets in `~/.env` or `~/.gitconfig.local` (outside chezmoi management).
- If a secret is accidentally staged, abort immediately and rotate it.
- Never log credential values, even in debug output.

## Dangerous shell commands

- Avoid `rm -rf` without explicit user approval and a stated recovery plan.
- Never run destructive DB commands (`DROP TABLE`, `DELETE FROM` without `WHERE`, `TRUNCATE`) without a schema backup confirmed first.
- Prefer dry-run flags (`--dry-run`, `-n`) when available before executing destructive operations.

## Dependencies

- Do not add dependencies with known critical CVEs.
- Pin versions in lockfiles; do not use floating ranges for production dependencies.
- Prefer well-maintained packages (last commit < 1 year, active issue tracker).

## Code injection

- Sanitize all user-controlled input before passing to shell commands, SQL, or eval.
- Avoid `eval` and dynamic `require`/`import` with user-supplied strings.
- Template strings that include user input must be parameterized (prepared statements, not concatenation).

## Authentication and authorization

- Never implement custom crypto — use established libraries.
- Enforce authorization checks server-side; do not rely solely on client-side gating.
- OAuth/OIDC tokens must not be stored in `localStorage` or cookies without `HttpOnly` + `Secure`.

## Prompt injection (AI-specific)

- Treat any user-supplied text that reaches an LLM prompt as untrusted.
- Do not include file contents or external data in system prompts without sanitization.
- Never store tool call results containing user input in persistent system context without review.
