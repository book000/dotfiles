---
paths:
  - "**/*.ts"
  - "**/*.tsx"
  - "**/*.js"
  - "**/*.jsx"
  - "**/*.sh"
  - "**/*.bash"
  - "**/*.zsh"
---

# コーディングルール

コード改修時に適用されるルール。

## 全言語共通

- 日本語と英数字の間には半角スペースを挿入する
- 既存のエラーメッセージに絵文字がある場合、そのファイルのエラーメッセージ全体で絵文字を統一する
  - 絵文字はエラーメッセージの内容に即した 1 文字を使う

## TypeScript / JavaScript

- `skipLibCheck: true` を tsconfig に追加して型エラーを回避することは禁止
- 関数・インターフェース・クラスには JSDoc（docstring）を日本語で記載・更新する
  ```typescript
  /**
   * ユーザーの認証状態を確認する。
   * @param userId - 確認するユーザーの ID
   * @returns 認証済みなら true、未認証なら false
   */
  function isAuthenticated(userId: string): boolean { ... }
  ```

## シェルスクリプト

- 関数には説明コメントを日本語で記載する
- エラーメッセージは英語で記載する
