---
paths:
  - "**/Dockerfile"
  - "**/Dockerfile.*"
  - "**/*.Dockerfile"
---

# Dockerfile Coding Rules

## Lint

- Code must pass hadolint default rules
  - CI uses `reusable-hadolint-ci.yml` from `book000/templates`
  - Do not add a dedicated config file (e.g. `.hadolint.yaml`)
