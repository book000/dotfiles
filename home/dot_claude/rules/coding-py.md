---
paths:
  - "**/*.py"
---

# Python コーディングルール

## フォーマット

- インデントは半角スペース 4 つ

## Lint

- flake8 のエラーサブセットを通すこと

  ```bash
  flake8 . --count --select=E1,E2,E3,E4,E7,E9,W1,W2,W3,W4,W5,F63,F7,F82 --show-source --statistics
  ```

  構文エラー・論理エラー系のみ強制。フル PEP8 スタイルは強制しない。

## ドキュメント

- 関数・クラスには docstring を日本語で記載する
