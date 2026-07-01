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

- Applies to step-level Action references (`steps[].uses`) — not the
  reusable-workflow calls in the previous section, which intentionally stay
  on `@master`.
- Pin every Action (including first-party `actions/*`) to a full-length commit SHA
  with a version comment, per [GitHub's secure-use guidance](https://docs.github.com/en/actions/security-for-github-actions/security-guides/security-hardening-for-github-actions).
  Renovate (`book000/templates//renovate/base`, preset
  `helpers:pinGitHubActionDigestsToSemver`) manages these — don't hand-edit SHAs.

  ```yaml
  # good (SHA and version comment refer to the same release)
  - uses: actions/checkout@8e8c483db84b4bee98b60c0593521ed34d9990e8 # v6.0.1

  # bad
  - uses: actions/checkout@v6
  - uses: actions/checkout@main
  ```

## Node.js Version

- Use `node-version-file: .node-version` for Node setup (do not hard-code the version)

  ```yaml
  - uses: actions/setup-node@2028fbc5c25fe9cf00d9f06a71cc4710d4507903 # v6.0.0
    with:
      node-version-file: .node-version
  ```

## Step Names

- Default to plain step names: sentence case, English, imperative-verb phrasing,
  no trailing punctuation. Do not add an emoji prefix by default.
- If a file already uses emoji-prefixed steps (e.g. following
  `book000/templates`), keep the whole file consistent — don't mix emoji and
  plain steps — and reuse this mapping instead of inventing new emoji:

  | Emoji | Purpose |
  |---|---|
  | 🛎 / 📥 | Checkout |
  | 🏗 / 🏗️ | Setup runtime / build |
  | 👨🏻‍💻 | Install dependencies |
  | 📂 | Cache / path lookup |
  | 👀 | Lint / status check |
  | 🧪 | Test |
  | 📦 | Package / artifact / release |
  | 🚀 | Deploy |
  | 🔄 | Update status |
  | 🏷️ | Version bump / tag |
  | 🔑 | Login / auth |

  ```yaml
  # good (plain, the default)
  - name: Checkout
  - name: Install dependencies

  # good (emoji, only matching an existing file convention)
  - name: 🛎 Checkout
  - name: 📦 Install dependencies

  # bad (mixed styles in one file)
  - name: 🛎 Checkout
  - name: Install dependencies
  ```

## Permissions

- Set `permissions` explicitly (workflow- and/or job-level); do not rely on
  the repository default. Grant only the scopes a job needs.

  ```yaml
  permissions: {}       # no token access needed

  permissions:
    contents: read       # e.g. checkout-only jobs

  jobs:
    release:
      permissions:
        contents: write  # scoped up only for the job that needs it
  ```

## Concurrency

- Use this group shape to cancel superseded runs:

  ```yaml
  concurrency:
    group: ${{ github.workflow }}-${{ github.event_name }}-${{ github.event.pull_request.number || github.ref }}
    cancel-in-progress: true
  ```

- Include `github.event_name` whenever a workflow can be triggered by both
  `pull_request` and `pull_request_target` — otherwise they share a group and
  cancel each other.
- For deploys that must not be cancelled mid-way (e.g. GitHub Pages), use a
  stable group with `cancel-in-progress: false`:

  ```yaml
  concurrency:
    group: pages
    cancel-in-progress: false
  ```

## Untrusted Input in `run:` Steps

- Never interpolate `${{ ... }}` from untrusted context (issue/PR
  titles/bodies, branch names, commit messages) directly into `run:`. Pass it
  through `env:` instead.

  ```yaml
  # bad
  - run: echo "Title is ${{ github.event.issue.title }}"

  # good
  - env:
      TITLE: ${{ github.event.issue.title }}
    run: echo "Title is $TITLE"
  ```

## `pull_request_target`

- Avoid it unless a job genuinely needs a privileged token/secrets while
  reacting to a fork PR. Prefer `pull_request`, or split privileged
  post-processing into a separate `workflow_run` workflow that only reads
  artifacts rather than checking out untrusted code with elevated permissions.
