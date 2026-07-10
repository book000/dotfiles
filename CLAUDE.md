## 目的

Claude Code の作業方針と、このリポジトリ固有のルールを示します。

## プロジェクト概要

- 目的: chezmoi で dotfiles と AI エージェント設定を管理する。
- 主な機能: シェル設定、tmux 設定、通知設定、エージェント設定のテンプレート化。

## 開発コマンド

- `package.json` は存在しない。ビルド工程はなく、`chezmoi apply` でデプロイする。
- ローカル検証は Docker 上で `chezmoi apply` を実行して結果を確認する。
- テストは `tests/` 配下のシェルスクリプトを直接実行する(下記「テスト」参照)。

## アーキテクチャと主要ファイル

- `home/`: chezmoi のソース。
- `home/dot_*`: 実際の dotfiles を `dot_` で表現。
- `home/dot_*/*.tmpl`: テンプレートファイル。
- `home/dot_*/*.d`: 追加設定の分割配置。

## chezmoi のファイル命名規則

chezmoi はソース側のプレフィックスを解釈してデプロイする。主なプレフィックス:

| ソースファイル名 | デプロイ後のファイル名 | 備考 |
|---|---|---|
| `executable_foo.sh` | `foo.sh` (実行可能) | `executable_` は除去される |
| `dot_foo` | `.foo` | `dot_` は `.` に変換される |
| `symlink_foo` | `foo` (シンボリックリンク) | リンク先はファイル内容 |

**重要**: `executable_` プレフィックスはデプロイ時に除去される。そのため、スクリプトを外部から呼び出す設定ファイル (`settings.json` など) では、`executable_` を付けずにパスを記述すること。

```jsonc
// 正しい
{"command": "bash ~/.claude/hooks/foo.sh"}

// 誤り（chezmoi 適用後にファイルが存在しない）
{"command": "bash ~/.claude/hooks/executable_foo.sh"}
```

`symlink_executable_` パターン（シンボリックリンクで `executable_` 付きの名前を作る回避策）は使用しない。

## 実装パターン

推奨:
- シェル設定は `.d` ディレクトリに分割する。

非推奨:
- 秘密情報の平文コミット。
- 一括で巨大な設定ファイルに追記する。

## コーディング規約

- 言語: Bash / Zsh。
- コミットメッセージは Conventional Commits に従い、`<description>` は日本語で記載する。
- コード内コメントは日本語、エラーメッセージは英語で記載する。
- 日本語と英数字の間には半角スペースを挿入する。
- 既存ファイルの構成・命名パターンに合わせる。

## テスト

- `tests/` 配下にシェルスクリプトのテストがあり、以下の 3 系統に分かれる:
  - `tests/syntax/`: `test_bash_syntax.sh` / `test_shellcheck.sh` / `test_json_schema.sh`(構文・shellcheck・JSON スキーマ)。
  - `tests/unit/`: `test_install.sh` / `test_notifications.sh` / `test_hooks.sh`(単体テスト)。
  - `tests/integration/`: `test_chezmoi_apply.sh`(`chezmoi apply` の統合テスト)。
- CI は `.github/workflows/` の `unit-test.yml` / `integration-test.yml` / `pr-checks.yml` で pull_request 時に自動実行される(`unit-test.yml` / `integration-test.yml` は master への push 時にも実行)。
- 通知・フック関連スクリプト(`home/dot_claude/scripts/`、`home/dot_claude/hooks/`、`home/dot_codex/` 等)や `home/bin/` のヘルパーを変更・削除した場合、対応するテストの参照が古くなっていないか確認する。
- 変更後はローカルでも Docker 上で `chezmoi apply` を実行して結果を確認する。

## ドキュメント更新ルール

- リポジトリ構成・コマンド・テスト・セキュリティ方針を変えたときは、実態に合わせて次のドキュメントを更新する:
  - `README.md`: 利用者向けの手順・機能説明。
  - `CLAUDE.md`: Claude Code 向けの作業方針(このファイル)。
  - `.github/copilot-instructions.md`: GitHub Copilot のコードレビュー観点。
- エージェント向けの指示は `CLAUDE.md` と `.github/copilot-instructions.md` の 2 点に集約する(旧 `AGENTS.md` は廃止済み)。

## リポジトリ固有

- Git 設定は `~/.gitconfig.local` で管理（chezmoi 管理外）。
- 通知系の環境変数は `~/.env` で管理（chezmoi 管理外）。
- `.env.example` と `.gitconfig.local.example` をサンプルとして提供。
- wakatime は別途管理するため、dotfiles での暗号化管理は行わない。
- PR 作成先は `upstream` remote があればそれを既定とし、`home/bin/executable_gh-pr-target-repo.sh`（デプロイ後 `~/bin/gh-pr-target-repo.sh`）で解決する。

## Claude Code フック / 通知機能

Claude Code のフックは `home/dot_claude/private_settings.json` で設定され、`Stop` / `PreToolUse` / `PostToolUse` / `PermissionRequest` / `Notification` / `UserPromptSubmit` を使う。役割は大きく 2 系統:

- **Discord 通知**: `home/dot_claude/scripts/completion-notify/` 配下のスクリプト(セッション完了、権限リクエスト、AskUserQuestion、Notification 等)。`~/.env` の `DISCORD_CLAUDE_WEBHOOK` と `DISCORD_CLAUDE_MENTION_USER_ID` を使用する。
- **レビュー強制など**: `home/dot_claude/hooks/` 配下のスクリプト(deep-review、レビュースレッド未解決チェック、rtk 書き換え等)。

フックのコマンドや対象スクリプトを変更したときは、`tests/unit/test_hooks.sh` / `test_notifications.sh` の参照が古くなっていないか確認する。
