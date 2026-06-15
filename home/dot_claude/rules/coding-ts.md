---
paths:
  - "**/*.ts"
  - "**/*.tsx"
  - "**/*.js"
  - "**/*.jsx"
  - "**/*.mjs"
  - "**/*.cjs"
---

# TypeScript / JavaScript Coding Rules

## Prohibited

- Adding `skipLibCheck: true` to tsconfig to suppress type errors is forbidden

## Documentation

- Write and maintain JSDoc (docstring) for all functions, interfaces, and classes. Language: follow the project CLAUDE.md if it specifies one; otherwise Japanese

  ```typescript
  /**
   * ユーザーの認証状態を確認する。
   * @param userId - 確認するユーザーの ID
   * @returns 認証済みなら true、未認証なら false
   */
  function isAuthenticated(userId: string): boolean { ... }
  ```

## Lint / Format

- Write lint config in `eslint.config.mjs` using flat config (no legacy `.eslintrc.*`)
  - Standard setup: `export { default } from '@book000/eslint-config'`
- Prettier config (`.prettierrc.yml` facts):
  - No semicolons (`semi: false`)
  - Single quotes (`singleQuote: true`)
  - Trailing commas es5 (`trailingComma: 'es5'`)
  - Print width 80 (`printWidth: 80`)
  - Indent 2 spaces (`tabWidth: 2`)
  - Arrow function arguments always parenthesized (`arrowParens: 'always'`)
  - LF line endings (`endOfLine: 'lf'`)

## ESLint Rules (not auto-fixable)

- **No floating promises** (`no-floating-promises`): add `void` to Promises that are not awaited

  ```typescript
  // bad
  fetchData()

  // good
  void fetchData()
  await fetchData()
  ```

- **catch variable name** (`unicorn/catch-error-name`): use `error` (or `err`)

  ```typescript
  try { ... } catch (error) { ... }
  ```

- **No redundant conditions** (`no-unnecessary-condition`): do not write conditions whose truthiness is always determined by the type
- **No use before define** (`no-use-before-define`): define functions and variables before use
- **`any`**: permitted, but add types where they can be added
- **`null`**: permitted (`unicorn/no-null` is off)
- **Abbreviations** (`dev`, `prod`, etc.): no need to expand (`prevent-abbreviations` is off)

## tsconfig

Maintain the following strict options:

- `strict`
- `noUnusedLocals`
- `noUnusedParameters`
- `noImplicitReturns`
- `noFallthroughCasesInSwitch`
- `esModuleInterop`
- Line endings: LF (`newLine: 'lf'`)

## Toolchain

- Package manager: **pnpm** (`only-allow pnpm` guard)
- Test runner: **jest**
- Node version: pinned in `.node-version`
