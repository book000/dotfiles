## 概要

chezmoi で dotfiles と AI エージェント設定を管理するためのリポジトリです。

## レイアウト

- `home/`: chezmoi のソース（汎用的な設定）
- `home/dot_*`: 実ファイルを `dot_` で表現
- `home/dot_*/*.tmpl`: テンプレート
- `home/dot_*/*.d`: 分割設定

## プロジェクト向けプロンプト

このリポジトリに対するプロンプトはプロジェクトルートに配置します。

- `CLAUDE.md`
- `AGENTS.md`
- `GEMINI.md`
- `.github/copilot-instructions.md`

`home/` 配下にあるプロンプトは、配布先（ユーザー環境）の汎用設定です。

## 初回セットアップ

### 1. Git 設定

`~/.gitconfig.local` を作成し、ユーザー情報を設定してください：

```bash
cp ~/.gitconfig.local.example ~/.gitconfig.local
vi ~/.gitconfig.local
```

設定例:
```ini
[user]
    name = Your Name
    email = your.email@example.com
```

### 2. 環境変数設定（オプション）

通知機能を使用する場合は、`~/.env` を作成してください：

```bash
cp ~/.env.example ~/.env
vi ~/.env
```

設定例:
```bash
DISCORD_CLAUDE_WEBHOOK="https://discord.com/api/webhooks/xxxxx/xxxxx"
DISCORD_CLAUDE_MENTION_USER_ID="123456789012345678"
```

**注意:** `~/.env` は機密情報を含むため、Git にコミットしないでください。

### 3. chezmoi apply

設定ファイルを適用します：

```bash
chezmoi apply
```
