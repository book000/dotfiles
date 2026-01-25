## 目的

`.bashrc.d` / `.bash_profile.d` / `.zshrc.d` / `.zprofile.d` の各ディレクトリに
追加設定を分割して配置します。

## 読み込み順

各シェルの本体ファイル（`.bashrc` など）から、
`LC_ALL=C` でソートした順に読み込みます。
読み込み順はファイル名の辞書順で決まります。

例:

- `00-path.sh`
- `10-history.sh`
- `20-aliases.sh`
