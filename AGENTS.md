## 目的

この dotfiles リポジトリに対する AI エージェント共通の作業方針を定義します。

## 開発手順（概要）

1. リポジトリ構成を把握する。
2. `home/` 配下のテンプレートや設定ファイルを更新する。
3. 影響範囲を確認する。
4. Docker で `chezmoi apply` を実行して結果を確認する。

## リポジトリ固有

- 目的: chezmoi で dotfiles と AI エージェント設定を管理する。
- `home/` 配下が chezmoi のソースであり、実ファイルは `dot_` プレフィックスで管理する。
- エージェント固有の指示やワークフローは、それぞれの prompt ファイルにのみ記載する。
- `upstream` remote がある場合、PR 作成先は upstream を既定とし、`gh-pr-target-repo.sh` で解決する。
- `.env` は `~/.env.example` をコピーして手動で作成する（chezmoi 管理外）。
- Git 設定は `~/.gitconfig.local.example` をコピーして手動で作成する（chezmoi 管理外）。
