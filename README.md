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

## age 暗号化の使い方

このリポジトリは `chezmoi` の age 暗号化を使う前提で構成しています。
機密情報（Discord Webhook / WakaTime API Key など）は暗号化して管理します。
`home/encrypted_dot_wakatime.cfg.age` は暗号化済みファイルとしてコミットします。

### セットアップ手順（各マシンごと）

1. age 鍵を作成

```
age-keygen -o ~/.config/chezmoi/key.txt
```

2. 公開鍵を `~/.config/chezmoi/chezmoi.toml` に設定

```
[age]
  recipient = "age1..."
```

3. 暗号化ファイルを作成（例: Discord Webhook）

```
chezmoi add --encrypt ~/.config/notify/gemini.env
```

4. `key.txt.age` をこのリポジトリのルートに配置

```
cp ~/.config/chezmoi/key.txt.age ./key.txt.age
```

`run_onchange_before_decrypt-private-key.sh.tmpl` が `key.txt.age` を復号して
`~/.config/chezmoi/key.txt` を作成します。

### マシンごとの Webhook

Discord Webhook は各マシンの `~/.config/chezmoi/chezmoi.toml` で設定してください。
この値は Git に入れず、ローカルで管理する前提です。
