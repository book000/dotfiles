---
paths:
  - ".github/workflows/*.yml"
  - ".github/workflows/*.yaml"
---

# GitHub Actions コーディングルール

## 共通 CI の再利用

- 共通 CI は自前で複製せず、`book000/templates` の reusable workflow を `@master` 参照で呼ぶ

  ```yaml
  uses: book000/templates/.github/workflows/reusable-nodejs-ci-pnpm.yml@master
  uses: book000/templates/.github/workflows/reusable-docker.yml@master
  uses: book000/templates/.github/workflows/reusable-hadolint-ci.yml@master
  ```

## Action のバージョン参照

- Action はメジャーバージョンタグで参照する

  ```yaml
  # 良い例
  uses: actions/checkout@v6
  uses: actions/setup-node@v6
  uses: actions/cache@v5

  # 悪い例（バージョン未指定）
  uses: actions/checkout@main
  ```

## Node.js バージョン

- Node セットアップは `node-version-file: .node-version` を使う（バージョンの直書き禁止）

  ```yaml
  - uses: actions/setup-node@v6
    with:
      node-version-file: .node-version
  ```

## ステップ名

- ステップ名には内容に即した絵文字プレフィックスを付ける

  ```yaml
  - name: 🛎 Checkout
  - name: 🏗 Setup node
  - name: 📦 Install dependencies
  - name: 🔍 Lint
  - name: 🧪 Test
  ```
