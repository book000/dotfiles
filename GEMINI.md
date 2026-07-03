## 目的

この dotfiles リポジトリ向けのコンテキストと作業方針を定義します。

## プロジェクト概要

- 目的: chezmoi で dotfiles と AI エージェント設定を管理する。
- 主な機能: シェル設定、tmux 設定、通知設定、エージェント設定のテンプレート化。

## リポジトリ固有

- `home/` 配下が chezmoi のソース。
- エージェント用プロンプトは `CLAUDE.md` / `AGENTS.md` / `GEMINI.md` / `.github/copilot-instructions.md` に配置する。
- エージェント固有の指示やワークフローは、それぞれの prompt ファイルにのみ記載する。
- `upstream` remote がある場合、PR 作成先は upstream を既定とし、`gh-pr-target-repo.sh` で解決する。
