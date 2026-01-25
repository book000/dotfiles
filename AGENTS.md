# AI エージェント共通ルール

## 目的

このドキュメントは、一般的な AI エージェントがこのプロジェクトで作業を行う際の共通の作業方針を定義します。

## 基本方針

### 言語

- **会話言語**: 日本語
- **コード内コメント**: 日本語
- **エラーメッセージ**: 英語
- **日本語と英数字の間**: 半角スペースを挿入

### コミット規約

- **コミットメッセージ**: [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/) に従う
  - `<type>(<scope>): <description>` 形式
  - `<description>` は日本語で記載
  - 例: `feat: ユーザー認証機能を追加`

### ブランチ命名

- **ブランチ命名**: [Conventional Branch](https://conventional-branch.github.io) に従う
  - `<type>/<description>` 形式
  - `<type>` は短縮形（feat, fix）を使用
  - 例: `feat/add-user-auth`

## 判断記録のルール

判断を行う際は、必ず以下を記録すること：

1. **判断内容の要約**: 何を決定したかを明確に記載
2. **検討した代替案**: 他にどのような選択肢があったかをリストアップ
3. **採用しなかった案とその理由**: なぜその案を選ばなかったかを説明
4. **前提条件・仮定・不確実性**: 判断の前提となる情報を明示
5. **レビューの必要性**: 他のエージェントやユーザーによるレビューが必要かを判断

**重要**: 前提・仮定・不確実性を明示すること。仮定を事実のように扱ってはならない。

## プロジェクト概要

- **目的**: chezmoi を使用して個人の dotfiles と AI エージェント設定を一元管理する
- **主な機能**:
  - シェル設定（bash/zsh）の集中管理
  - AI エージェント設定の同期
  - 機密情報の暗号化管理
  - ツール設定（tmux、vim、git など）の統一

## 技術スタック

- **ツール**: chezmoi（dotfiles 管理フレームワーク）
- **暗号化**: age（最小限の暗号化ツール）
- **シェル**: Bash / Zsh
- **テンプレート**: Go template（chezmoi 組み込み）

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

## 開発手順（概要）

### 1. プロジェクトの理解

- リポジトリの構造を確認する
- chezmoi の命名規則を理解する（`dot_` プレフィックス、`.tmpl` サフィックス、`.age` サフィックス）
- 既存の設定ファイルのパターンを把握する

### 2. 変更の実装

- 既存のコーディングスタイルに従う
- chezmoi テンプレート構文（Go template）を使用する
- 設定分割パターン（`.d/` ディレクトリ）に従う

### 3. 動作確認

- `chezmoi apply --dry-run` でドライラン確認
- Docker コンテナでの動作確認を推奨
- シェルスクリプトの構文エラーチェック（`bash -n`）

### 4. コミットと PR

- Conventional Commits に従ったコミットメッセージ
- Conventional Branch に従ったブランチ命名
- センシティブな情報がコミットされていないことを確認

## セキュリティ / 機密情報

### 認証情報のコミット禁止

- API キーや認証情報は age で暗号化して管理する
  - WakaTime API キー: `encrypted_dot_wakatime.cfg.age`
  - Discord Webhook URL: `.chezmoi.toml.tmpl` でテンプレート管理
- age 秘密鍵（`key.txt`）はローカルのみ保管（リポジトリにコミットしない）

### ログへの機密情報出力禁止

- エラーメッセージに機密情報を含めない
- デバッグ出力に認証情報を表示しない

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
