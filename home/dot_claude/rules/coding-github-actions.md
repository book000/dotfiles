---
paths:
  - ".github/workflows/*.yml"
  - ".github/workflows/*.yaml"
---

# GitHub Actions Coding Rules

## Reusable Workflows

- Do not duplicate common CI — call reusable workflows from `book000/templates` with `@master`

  ```yaml
  uses: book000/templates/.github/workflows/reusable-nodejs-ci-pnpm.yml@master
  uses: book000/templates/.github/workflows/reusable-docker.yml@master
  uses: book000/templates/.github/workflows/reusable-hadolint-ci.yml@master
  ```

## Action Version References

- Reference Actions by major version tag

  ```yaml
  # good
  uses: actions/checkout@v6
  uses: actions/setup-node@v6
  uses: actions/cache@v5

  # bad (no pinned version)
  uses: actions/checkout@main
  ```

## Node.js Version

- Use `node-version-file: .node-version` for Node setup (do not hard-code the version)

  ```yaml
  - uses: actions/setup-node@v6
    with:
      node-version-file: .node-version
  ```

## Step Names

- Prefix step names with an emoji matching the step's content

  ```yaml
  - name: 🛎 Checkout
  - name: 🏗 Setup node
  - name: 📦 Install dependencies
  - name: 🔍 Lint
  - name: 🧪 Test
  ```
