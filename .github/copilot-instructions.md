# GitHub Copilot Instructions

## プロジェクト概要
- 目的: chezmoi で dotfiles と AI エージェント設定を管理する。
- 主な機能: シェル設定（Bash/Zsh）、tmux 設定、通知設定、エージェント設定のテンプレート化。
- 対象ユーザー: 自分用の開発環境を効率的に管理・共有したい開発者。

## 共通ルール
- 会話は日本語で行う。
- PR とコミットは Conventional Commits に従う。
- 日本語と英数字の間には半角スペースを入れる。

## 技術スタック
- ツール: chezmoi, git, tmux, age (暗号化)
- 言語: Bash, Zsh, Vim script
- 設定形式: TOML (chezmoi), JSON (エージェント設定)

## コーディング規約
- フォーマット: 既存ファイルのスタイル（インデント、命名規則）に合わせる。
- 命名規則: chezmoi の慣習に従い、実ファイルには `dot_` プレフィックスを付与する。
- コメント: 日本語で記載する。
- エラーメッセージ: 英語で記載する。

## 開発コマンド
このプロジェクトには `package.json` は存在しません。主な操作は `chezmoi` コマンドで行います。
```bash
# 設定の適用（ドライラン）
chezmoi apply --dry-run

# 設定の適用
chezmoi apply

# 秘密情報の追加（暗号化）
chezmoi add --encrypt <file>

# 状態の確認
chezmoi status
```

## テスト方針
- 自動テストフレームワークは導入されていません。
- 変更後は `chezmoi apply --dry-run` で差分を確認し、必要に応じて Docker 環境などで動作確認を行います。

## セキュリティ / 機密情報
- Discord Webhook や API キーなどの機密情報は、`age` で暗号化するか、テンプレート変数を使用してローカルの `chezmoi.toml` で管理し、絶対に出力やコミットを行わない。
- ログに機密情報を出力しない。

## ドキュメント更新
- `README.md`: セットアップ手順や新機能の追加時。
- `CLAUDE.md` / `AGENTS.md` / `GEMINI.md` / `.github/copilot-instructions.md`: ルールやコマンドの変更時。

## リポジトリ固有
- `home/` 配下が chezmoi のソースディレクトリである。
- `.env` は `dot_env.tmpl` を使用して動的に生成する。
- テンプレートファイル (`.tmpl`) を編集する際は、chezmoi のテンプレート構文に注意する。