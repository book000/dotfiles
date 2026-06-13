---
paths:
  - "**/*.ts"
  - "**/*.tsx"
  - "**/*.js"
  - "**/*.jsx"
  - "**/*.mjs"
  - "**/*.cjs"
---

# TypeScript / JavaScript コーディングルール

## 禁止事項

- `skipLibCheck: true` を tsconfig に追加して型エラーを回避することは禁止

## ドキュメント

- 関数・インターフェース・クラスには JSDoc（docstring）を日本語で記載・更新する

  ```typescript
  /**
   * ユーザーの認証状態を確認する。
   * @param userId - 確認するユーザーの ID
   * @returns 認証済みなら true、未認証なら false
   */
  function isAuthenticated(userId: string): boolean { ... }
  ```

## Lint / Format

- Lint 設定は `eslint.config.mjs` に flat config で記述する（レガシー `.eslintrc.*` は使わない）
  - 標準構成: `export { default } from '@book000/eslint-config'`
- Prettier 設定（`.prettierrc.yml` の事実）:
  - セミコロンなし（`semi: false`）
  - シングルクォート（`singleQuote: true`）
  - 末尾カンマ es5（`trailingComma: 'es5'`）
  - 行幅 80（`printWidth: 80`）
  - インデント半角スペース 2（`tabWidth: 2`）
  - アロー関数の引数は常に括弧（`arrowParens: 'always'`）
  - 改行 LF（`endOfLine: 'lf'`）

## ESLint ルール（自動修正不可のもの）

- **Promise の放置禁止**（`no-floating-promises`）: `await` しない Promise は `void` を付ける

  ```typescript
  // 悪い例
  fetchData()

  // 良い例
  void fetchData()
  await fetchData()
  ```

- **catch 変数名**（`unicorn/catch-error-name`）: `error` に統一する（`err` も可）

  ```typescript
  try { ... } catch (error) { ... }
  ```

- **冗長条件の禁止**（`no-unnecessary-condition`）: 型上必ず真偽が決まる条件を書かない
- **使用前定義の禁止**（`no-use-before-define`）: 関数・変数は使用前に定義する
- **`any` の扱い**: `any` は許容されているが、型を付けられる箇所では型を付ける
- **`null`**: 使用可。`unicorn/no-null` は off
- **省略形（`dev`・`prod` 等）**: 展開不要。`prevent-abbreviations` は off

## tsconfig

以下の strict 系オプションを維持する:

- `strict`
- `noUnusedLocals`
- `noUnusedParameters`
- `noImplicitReturns`
- `noFallthroughCasesInSwitch`
- `esModuleInterop`
- 改行コード: LF（`newLine: 'lf'`）

## ツールチェーン

- パッケージマネージャ: **pnpm**（`only-allow pnpm` ガード）
- テスト: **jest**
- Node バージョン: `.node-version` ファイルで固定
