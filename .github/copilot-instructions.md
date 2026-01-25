# GitHub Copilot Instructions

## プロジェクト概要

- 目的: chezmoi で dotfiles と AI エージェント設定を管理する。
- 主な機能: シェル設定、tmux 設定、通知設定のテンプレート化。
- 対象ユーザー: 自分用の開発環境を管理するユーザー。

## 共通ルール

- 会話は日本語で行う。
- コード内コメントは日本語で記載する。
- エラーメッセージは英語で記載する。
- 日本語と英数字の間には半角スペースを挿入する。
- コミットメッセージは Conventional Commits に従う（description は日本語）。

## 技術スタック

- 言語: Bash / Zsh
- ツール: chezmoi, git, tmux, jq

## コーディング規約

- 既存ファイルの構成に合わせる。
- `.env` は `dot_env.tmpl` を使用して生成する。
- 機密情報は平文でコミットしない。

## 開発コマンド

- `package.json` は存在しないため該当コマンドはない。
- 必要に応じて Docker 上で `chezmoi apply` を実行する。

## テスト方針

- 自動テストはない。
- 変更後は Docker 上で `chezmoi apply` を実行して結果を確認する。

## セキュリティ / 機密情報

- Discord Webhook や API キーは暗号化またはローカル設定で管理する。
- ログに機密情報を出力しない。

## ドキュメント更新

- `README.md`
- `CLAUDE.md` / `AGENTS.md` / `GEMINI.md` / `.github/copilot-instructions.md`

## リポジトリ固有

- `home/` 配下が chezmoi のソースであり、`dot_` プレフィックスでファイルを管理する。
