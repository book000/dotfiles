# GitHub Copilot Instructions

## プロジェクト概要

- 目的: chezmoi を使用して個人の dotfiles と AI エージェント設定を一元管理する
- 主な機能: シェル設定（bash/zsh）の集中管理、AI エージェント設定の同期、機密情報の暗号化管理
- 対象ユーザー: 開発者（個人用環境設定）

## 共通ルール

- 会話は日本語で行う。
- PR とコミットは Conventional Commits に従う。`<description>` は日本語で記載する。
  - 例: `feat: ユーザー認証機能を追加`
- ブランチ命名は Conventional Branch に従う。`<type>` は短縮形（feat, fix）を使用する。
  - 例: `feat/add-user-auth`
- 日本語と英数字の間には半角スペースを入れる。

## 技術スタック

- ツール: chezmoi（dotfiles 管理フレームワーク）
- 暗号化: age（最小限の暗号化ツール）
- シェル: Bash / Zsh
- テンプレート: Go template（chezmoi 組み込み）
- 対応 AI エージェント: Claude Code、Codex CLI、Gemini CLI、GitHub Copilot

## ディレクトリ構造

```
dotfiles/
├── .chezmoi.toml.tmpl              # chezmoi 設定テンプレート
├── .chezmoiignore                  # chezmoi が無視するファイル
├── .chezmoiroot                    # chezmoi ルートマーカー
├── home/                            # chezmoi ソース（実ファイルの定義）
│   ├── dot_bashrc                   # bash 設定
│   ├── dot_bashrc.d/                # bash 設定分割
│   ├── dot_zshrc                    # zsh 設定
│   ├── dot_zshrc.d/                 # zsh 設定分割
│   ├── dot_claude/                  # Claude Code 設定
│   ├── dot_codex/                   # Codex エージェント設定
│   ├── dot_gemini/                  # Gemini エージェント設定
│   └── dot_copilot/                 # GitHub Copilot 設定
└── run_onchange_before_decrypt-private-key.sh.tmpl  # 秘密鍵復号化フック
```

## コーディング規約

- **コメント**: 日本語で記載する
- **エラーメッセージ**: 英語で記載する
- **シェルスクリプト**: 既存のコーディングスタイルに従う
- **chezmoi テンプレート**: Go template 構文を使用する
  - ファイル名: `dot_` プレフィックスで `.` を表す
  - テンプレート: `.tmpl` サフィックス
  - 暗号化: `.age` サフィックス

## 開発コマンド

```bash
# chezmoi の初期化（新規マシン）
chezmoi init <repo> --branch <branch-name>

# ドライラン（変更内容の確認）
chezmoi apply --dry-run

# 設定の適用
chezmoi apply

# リポジトリの更新
chezmoi update

# 差分確認
chezmoi diff

# 設定ファイルの編集
chezmoi edit <file>

# 暗号化ファイルの編集
chezmoi edit --encrypt <file>
```

## テスト方針

- **テストフレームワーク**: なし（手動検証）
- **検証方法**: Docker コンテナでの動作確認を推奨
  ```bash
  docker run -it -v $(pwd):/dotfiles ubuntu:latest
  cd /dotfiles
  chezmoi apply --dry-run
  chezmoi apply
  ```
- **検証ポイント**:
  - テンプレート処理が正しく行われているか
  - 暗号化ファイルが復号化されているか
  - シェル起動時のエラーがないか

## セキュリティ / 機密情報

- **認証情報のコミット禁止**: API キーや認証情報は暗号化（age）して管理する
  - WakaTime API キー: `encrypted_dot_wakatime.cfg.age`
  - Discord Webhook URL: `.chezmoi.toml.tmpl` でテンプレート管理
- **ログへの機密情報出力禁止**: エラーメッセージに機密情報を含めない
- **age 秘密鍵の管理**: `key.txt` はローカルのみ保管（リポジトリにコミットしない）

## ドキュメント更新

コードや設定の変更時には、以下のドキュメントを更新する：

- `README.md`: プロジェクトの概要と使用方法
- `home/dot_bashrc.d/README.md`: bash 設定分割の説明
- `home/dot_zshrc.d/README.md`: zsh 設定分割の説明
- プロンプトファイル（`.github/copilot-instructions.md`、`CLAUDE.md`、`AGENTS.md`、`GEMINI.md`）

## リポジトリ固有

- **chezmoi の命名規則**:
  - `dot_` プレフィックス: `.` で始まるファイル名（例: `dot_bashrc` → `~/.bashrc`）
  - `.tmpl` サフィックス: chezmoi テンプレート処理対象
  - `.age` サフィックス: age 暗号化ファイル
- **設定分割パターン**:
  - `.d/` ディレクトリ内のファイルは `LC_ALL=C` でソート順に読み込まれる
  - 数字プレフィックスで読み込み順序を制御（例: `00-path.sh`、`10-history.sh`）
- **マルチエージェント対応**:
  - 各 AI エージェント専用のディレクトリを配置（`dot_claude/`、`dot_codex/`、`dot_gemini/`、`dot_copilot/`）
  - 各エージェント独立の設定ファイルとスクリプトを管理
- **Git Worktree**: このプロジェクトでは使用しない
