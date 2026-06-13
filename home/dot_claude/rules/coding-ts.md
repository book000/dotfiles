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
