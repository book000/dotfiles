# GitHub Copilot Instructions

このリポジトリは chezmoi で管理する dotfiles および AI エージェント設定リポジトリです。
コードレビュー時は以下の観点を優先的に確認してください。

## プロジェクト概要

- 目的: chezmoi でシェル設定・tmux 設定・通知設定・AI エージェント設定をテンプレート化して管理する。
- `tests/` 配下のシェルスクリプトで構文チェック・単体テスト・統合テストを行い、`.github/workflows/` (unit-test.yml / integration-test.yml / pr-checks.yml) により pull_request 時に CI で自動実行される。ローカルでは Docker 上で `chezmoi apply` を実行して結果を確認する。

## レビューで特に確認すること

### chezmoi のファイル命名規則(誤りやすい)

- `executable_foo.sh` はデプロイ後 `foo.sh` になり、`executable_` は除去される。`settings.json` など外部からパスを参照する設定で `executable_` を含めたパスを書いていないか確認する。
- `dot_foo` はデプロイ後 `.foo` になる。
- `symlink_foo` はシンボリックリンクになり、ファイル内容がリンク先を表す。
- `symlink_executable_` のような回避策パターンは使用しない。

### 秘密情報

- トークン・Webhook URL・パスワード等を平文でコミットしていないか確認する。
- `~/.env` や `~/.gitconfig.local` はリポジトリ管理外。`.env.example` / `.gitconfig.local.example` などサンプルのみを含める。
- pre-commit フック(`home/dot_config/git/hooks/executable_pre-commit`)や `home/dot_gitleaks.toml` の allowlist を変更する場合、誤検知抑制が広すぎて実際のシークレット検知を無効化していないか確認する。

### テストの追随

- `home/dot_codex/`、`home/dot_claude/scripts/` など通知・フック関連スクリプトを変更・削除した場合、`tests/unit/`、`tests/integration/`、`tests/syntax/` 配下の対応するテストが古い参照を残していないか確認する。

## コーディング規約

- コミットメッセージは Conventional Commits に従い、`<description>` は日本語で記載する。
- コード内コメントは日本語、エラーメッセージは英語で記載する。
- 日本語と英数字の間には半角スペースを挿入する。
- 既存ファイルの構成・命名パターンに合わせる。

## 技術スタック

- 言語: Bash
- ツール: chezmoi, git, tmux, jq

## ドキュメント整合性

- 変更内容が `README.md` / `CLAUDE.md` に記載のルールと矛盾していないか確認する。
