---
paths:
  - "**/Dockerfile"
  - "**/Dockerfile.*"
  - "**/*.Dockerfile"
---

# Dockerfile コーディングルール

## Lint

- hadolint のデフォルトルールを通すこと
  - CI は `book000/templates` の `reusable-hadolint-ci.yml` で検査している
  - 専用設定ファイル（`.hadolint.yaml` 等）は置かない
