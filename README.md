## age 暗号化の使い方

このリポジトリは `chezmoi` の age 暗号化を使う前提で構成しています。
機密情報（Discord Webhook / WakaTime API Key など）は暗号化して管理します。

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
chezmoi add --encrypt ~/.config/notify/discord.env
```

4. `key.txt.age` をこのリポジトリのルートに配置（必要なら .gitignore に追加）

```
cp ~/.config/chezmoi/key.txt.age ./key.txt.age
```

`run_onchange_before_decrypt-private-key.sh.tmpl` が `key.txt.age` を復号して
`~/.config/chezmoi/key.txt` を作成します。

### マシンごとの Webhook

Discord Webhook は各マシンの `~/.config/chezmoi/chezmoi.toml` で設定してください。
この値は Git に入れず、ローカルで管理する前提です。
