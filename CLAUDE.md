## 目的

Claude Code の作業方針と、このリポジトリ固有のルールを示します。

## プロジェクト概要

- 目的: chezmoi で dotfiles と AI エージェント設定を管理する。
- 主な機能: シェル設定、tmux 設定、通知設定、エージェント設定のテンプレート化。

## 開発コマンド

- `package.json` は存在しないため該当コマンドはない。
- 必要に応じて Docker 上で `chezmoi apply` を実行する。

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

## テスト

- 自動テストはない。
- 変更後は Docker 上で `chezmoi apply` を実行して結果を確認する。

## ドキュメント更新ルール

- `README.md`
- `CLAUDE.md` / `AGENTS.md` / `GEMINI.md` / `.github/copilot-instructions.md`

## リポジトリ固有

- Git 設定は `~/.gitconfig.local` で管理（chezmoi 管理外）。
- 通知系の環境変数は `~/.env` で管理（chezmoi 管理外）。
- `.env.example` と `.gitconfig.local.example` をサンプルとして提供。
- wakatime は別途管理するため、dotfiles での暗号化管理は行わない。

## Claude Code 通知機能

以下の Claude Code フックが設定されている:

1. **Stop フック**: セッション完了時に Discord 通知
2. **PermissionRequest フック**: 権限リクエスト時に Discord 通知
3. **Notification フック**: `permission_prompt` または `idle_prompt` 発生時に Discord 通知

通知には `~/.env` の `DISCORD_CLAUDE_WEBHOOK` と `DISCORD_CLAUDE_MENTION_USER_ID` を使用する。
