---
paths:
  - package.json
  - pnpm-lock.yaml
  - yarn.lock
  - package-lock.json
  - "**/*.ts"
  - "**/*.tsx"
  - "**/*.js"
  - "**/*.jsx"
---

# Context7 Rules

## When to Use

- Checking library/framework API specs (arguments, return values, deprecations, compatibility)
- Setup and configuration (e.g. Next.js / React / Vite / Prisma / AWS SDK)
- Version-sensitive content (e.g. Next.js 14/15, React 18/19)
- When an error may be caused by a documented API change

## When Not to Use

- When the task is mainly reading project-specific logic and no external spec check is needed
- General algorithms or language specs (ECMAScript/TypeScript basics) that need no doc lookup
- When using Context7 would add noise rather than help (e.g. trivial utility edits)

## Output Requirements When Used

- State the assumptions derived from the referenced docs (target version, preconditions)
- If uncertain, explicitly say so and list what needs further verification

## Handling Version Assumptions

- When presenting steps for a library or framework, always state the target version.
- If the user has not specified a version, determine it in this order:
  1. Infer from lockfile / package.json / go.mod in the repository
  2. If inference is not possible, state "unknown" and present both branches (e.g. v1 and v2)
- If a version difference is suspected, verify with Context7 before answering.
