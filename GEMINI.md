# Gemini CLI 作業方針

## 目的

このドキュメントは、Gemini CLI がこのプロジェクトで作業を行う際のコンテキストと作業方針を定義します。

## 出力スタイル

### 言語

- **会話言語**: 日本語
- **コード内コメント**: 日本語
- **エラーメッセージ**: 英語

### トーン

- 簡潔かつ明確な説明を心がける
- 技術的な正確さを優先する
- 前提条件や不確実性を明示する

### 形式

- マークダウン形式で出力する
- コードブロックは適切な言語指定を行う
- 日本語と英数字の間には半角スペースを挿入する

## 共通ルール

- **会話は日本語で行う**
- **コミットメッセージ**: [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/) に従う
  - `<type>(<scope>): <description>` 形式
  - `<description>` は日本語で記載
  - 例: `feat: ユーザー認証機能を追加`
- **ブランチ命名**: [Conventional Branch](https://conventional-branch.github.io) に従う
  - `<type>/<description>` 形式
  - `<type>` は短縮形（feat, fix）を使用
  - 例: `feat/add-user-auth`
- **日本語と英数字の間**: 半角スペースを挿入する

## プロジェクト概要

- **目的**: chezmoi を使用して個人の dotfiles と AI エージェント設定を一元管理する
- **主な機能**:
  - シェル設定（bash/zsh）の集中管理
  - AI エージェント（Claude Code、Codex、Gemini、GitHub Copilot）の設定を同期
  - 機密情報（API キー、Webhook）の暗号化管理
  - tmux、vim、git などのツール設定を統一

## 技術スタック

- **ツール**: chezmoi（dotfiles 管理フレームワーク）
- **暗号化**: age（最小限の暗号化ツール）
- **シェル**: Bash / Zsh
- **テンプレート**: Go template（chezmoi 組み込み）
- **対応 AI エージェント**: Claude Code、Codex CLI、Gemini CLI、GitHub Copilot

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
age-keygen -o ~/.config/chezmoi/key.txt
chezmoi init <repo> --branch <branch-name>
chezmoi apply

# ドライラン（変更内容の確認）
chezmoi apply --dry-run

# 設定の適用
chezmoi apply

# リポジトリの更新
chezmoi update
chezmoi apply

# 差分確認
chezmoi diff

# 設定ファイルの編集
chezmoi edit <file>

# 暗号化ファイルの編集
chezmoi edit --encrypt <file>
```

## 注意事項

### セキュリティ / 機密情報

- **認証情報のコミット禁止**: API キーや認証情報は age で暗号化して管理する
  - WakaTime API キー: `encrypted_dot_wakatime.cfg.age`
  - Discord Webhook URL: `.chezmoi.toml.tmpl` でテンプレート管理
- **ログへの機密情報出力禁止**: エラーメッセージに機密情報を含めない
- **age 秘密鍵の管理**: `key.txt` はローカルのみ保管（リポジトリにコミットしない）

### 既存ルールの優先

- プロジェクトの既存のコーディングスタイルを尊重する
- 既存の設定ファイルのパターンに従う
- 新しい機能を追加する場合は、既存の構造に統合する

### 既知の制約

- **テストフレームワーク**: なし（手動検証のみ）
- **CI/CD**: GitHub Actions は設定されていない
- **パッケージマネージャー**: なし（Shell scripts のみ）

## リポジトリ固有

### chezmoi の命名規則

- **`dot_` プレフィックス**: `.` で始まるファイル名（例: `dot_bashrc` → `~/.bashrc`）
- **`.tmpl` サフィックス**: chezmoi テンプレート処理対象
- **`.age` サフィックス**: age 暗号化ファイル

### 設定分割パターン

- シェル設定は `.d/` ディレクトリ内に分割管理
- ファイルは `LC_ALL=C` でソート順に読み込まれる
- 数字プレフィックスで読み込み順序を制御（例: `00-path.sh`、`10-history.sh`）

### 暗号化戦略

- age で機密情報を暗号化
- `run_onchange_before_decrypt-private-key.sh.tmpl` で自動復号化
- chezmoi テンプレートでマシンごとにカスタマイズ可能

### マルチシェル対応

- bash と zsh の両方に対応
- `.d/` 分割設定で共通管理
- シェル固有の設定は各シェルのディレクトリに配置

### マルチエージェント対応

- 各 AI エージェント専用のディレクトリを配置
  - `dot_claude/`: Claude Code 設定
  - `dot_codex/`: Codex エージェント設定
  - `dot_gemini/`: Gemini エージェント設定
  - `dot_copilot/`: GitHub Copilot 設定
- 各エージェント独立の設定ファイルとスクリプトを管理

### テンプレート化

- git ユーザー情報や Discord Webhook は chezmoi テンプレートでマシンごとにカスタマイズ可能
- `.chezmoi.toml.tmpl` で chezmoi init 時にプロンプト入力
- 機密情報は age で暗号化し、テンプレートで動的に生成
