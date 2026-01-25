# Claude Code 作業方針

## 目的

このドキュメントは、Claude Code がこのプロジェクトで作業を行う際の方針とルールを定義します。判断の記録と透明性を重視し、他のエージェントとの連携を促進します。

## 判断記録のルール

判断は必ずレビュー可能な形で記録すること：

1. **判断内容の要約**: 何を決定したかを明確に記載
2. **検討した代替案**: 他にどのような選択肢があったかをリストアップ
3. **採用しなかった案とその理由**: なぜその案を選ばなかったかを説明
4. **前提条件・仮定・不確実性**: 判断の前提となる情報を明示
5. **他エージェントによるレビュー可否**: Codex CLI や Gemini CLI によるレビューが必要かを判断

**重要**: 前提・仮定・不確実性を明示すること。仮定を事実のように扱ってはならない。

## プロジェクト概要

- **目的**: chezmoi を使用して個人の dotfiles と AI エージェント設定を一元管理する
- **主な機能**:
  - シェル設定（bash/zsh）の集中管理
  - AI エージェント（Claude Code、Codex、Gemini、GitHub Copilot）の設定を同期
  - 機密情報（API キー、Webhook）の暗号化管理
  - tmux、vim、git などのツール設定を統一

## 重要ルール

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

## 環境のルール

- **GitHub リポジトリ調査**: テンポラリディレクトリに git clone してコード検索する
- **シェル環境**: Git Bash で動作（Windows 環境）
  - bash コマンドを使用する
  - PowerShell コマンドは明示的に `powershell -Command ...` または `pwsh -Command ...` を使用
- **Renovate PR の扱い**: Renovate が作成した既存のプルリクエストに対して、追加コミットや更新を行ってはならない

## Git Worktree について

このプロジェクトでは Git Worktree を採用していません。

## コード改修時のルール

- **日本語と英数字の間隔**: 半角スペースを挿入する
- **エラーメッセージの絵文字**: 既存のエラーメッセージに絵文字がある場合、全体で統一して設定する
- **docstring 記載**: 関数やインターフェースには docstring（JSDoc など）を日本語で記載・更新する

## 相談ルール

Codex CLI や Gemini CLI の他エージェントに相談することができます。以下の観点で使い分けてください。

### Codex CLI (ask-codex)

- 実装コードに対するソースコードレビュー
- 関数設計、モジュール内部の実装方針などの局所的な技術判断
- アーキテクチャ、モジュール間契約、パフォーマンス／セキュリティといった全体影響の判断
- 実装の正当性確認、機械的ミスの検出、既存コードとの整合性確認

### Gemini CLI (ask-gemini)

- SaaS 仕様、言語・ランタイムのバージョン差、料金・制限・クォータといった、最新の適切な情報が必要な外部依存の判断
- 外部一次情報の確認、最新仕様の調査、外部前提条件の検証

### 指摘への対応ルール

他エージェントが指摘・異議を提示した場合、Claude Code は必ず以下のいずれかを行う。**黙殺・無言での不採用は禁止する。**

- 指摘を受け入れ、判断を修正する
- 指摘を退け、その理由を明示する

以下は必ず実施する：

- 他エージェントの提案を鵜呑みにせず、その根拠や理由を理解する
- 自身の分析結果と他エージェントの意見が異なる場合は、双方の視点を比較検討する
- 最終的な判断は、両者の意見を総合的に評価した上で、自身で下す

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

## アーキテクチャと主要ファイル

### ディレクトリ構造

```
dotfiles/
├── .chezmoi.toml.tmpl              # chezmoi 設定テンプレート
├── .chezmoiignore                  # chezmoi が無視するファイル
├── .chezmoiroot                    # chezmoi ルートマーカー
├── home/                            # chezmoi ソース（実ファイルの定義）
│   ├── dot_bash_profile             # bash ログインシェル設定
│   ├── dot_bash_profile.d/          # bash ログイン設定分割
│   ├── dot_bashrc                   # bash インタラクティブシェル設定
│   ├── dot_bashrc.d/                # bash 設定分割（12 ファイル）
│   ├── dot_zprofile                 # zsh ログインシェル設定
│   ├── dot_zprofile.d/              # zsh ログイン設定分割
│   ├── dot_zshrc                    # zsh インタラクティブシェル設定
│   ├── dot_zshrc.d/                 # zsh 設定分割（5 ファイル）
│   ├── dot_p10k.zsh                 # powerlevel10k テーマ設定
│   ├── dot_tmux.conf                # tmux マルチプレクサ設定
│   ├── dot_vimrc                    # vim エディタ設定
│   ├── dot_gitconfig.tmpl           # git 設定（テンプレート）
│   ├── dot_gitignore_global         # git グローバル無視
│   ├── dot_ssh/config               # SSH 接続設定
│   ├── dot_claude/                  # Claude Code 設定
│   ├── dot_codex/                   # Codex エージェント設定
│   ├── dot_gemini/                  # Gemini エージェント設定
│   ├── dot_copilot/                 # GitHub Copilot 設定
│   ├── dot_config/                  # アプリケーション設定
│   └── encrypted_dot_wakatime.cfg.age # WakaTime 設定（暗号化）
└── run_onchange_before_decrypt-private-key.sh.tmpl  # 秘密鍵復号化フック
```

### 主要ファイル

- **`.chezmoi.toml.tmpl`**: chezmoi 初期化時のテンプレート（age 暗号化設定、git ユーザー情報、Discord Webhook 設定）
- **`.chezmoiignore`**: 配布対象外ファイル（ホワイトリスト形式）
- **`dot_bashrc` / `dot_zshrc`**: シェル設定のメインファイル
- **`dot_bashrc.d/` / `dot_zshrc.d/`**: シェル設定の分割管理（`LC_ALL=C` でソート順に読み込み）
- **`dot_gitconfig.tmpl`**: git 設定テンプレート
- **`dot_claude/`、`dot_codex/`、`dot_gemini/`、`dot_copilot/`**: 各 AI エージェント専用ディレクトリ
- **`run_onchange_before_decrypt-private-key.sh.tmpl`**: chezmoi apply 時に age 秘密鍵を自動復号化

## 実装パターン

### 推奨パターン

- **設定分割**: シェル設定は `.d/` ディレクトリ内に分割し、数字プレフィックスで読み込み順序を制御（例: `00-path.sh`、`10-history.sh`）
- **chezmoi 命名規則**:
  - `dot_` プレフィックス: `.` で始まるファイル名（例: `dot_bashrc` → `~/.bashrc`）
  - `.tmpl` サフィックス: chezmoi テンプレート処理対象
  - `.age` サフィックス: age 暗号化ファイル
- **機密情報管理**: age で暗号化し、`run_onchange` フックで自動復号化
- **テンプレート変数**: `.chezmoi.toml.tmpl` で chezmoi init 時にプロンプト入力

### 非推奨パターン

- **平文での機密情報保存**: API キーや認証情報を暗号化せずに保存しない
- **ハードコードされたユーザー情報**: git user.name や user.email をハードコードしない（テンプレート化する）
- **設定ファイルの肥大化**: 単一ファイルに全設定を記載せず、`.d/` ディレクトリで分割管理する

## テスト

### テスト方針

- **テストフレームワーク**: なし（手動検証）
- **検証方法**: Docker コンテナでの動作確認を推奨
  ```bash
  docker run -it -v $(pwd):/dotfiles ubuntu:latest
  cd /dotfiles
  chezmoi apply --dry-run
  chezmoi apply
  ```

### テスト追加条件

- 新しい設定ファイルや暗号化ファイルを追加した場合、Docker で動作確認を行う
- テンプレート処理が正しく行われているかを確認する
- シェル起動時のエラーがないかを確認する

## ドキュメント更新ルール

### 更新対象

以下のドキュメントは、関連する変更があった場合に必ず更新する：

- `README.md`: プロジェクトの概要と使用方法
- `home/dot_bashrc.d/README.md`: bash 設定分割の説明
- `home/dot_zshrc.d/README.md`: zsh 設定分割の説明
- プロンプトファイル（`.github/copilot-instructions.md`、`CLAUDE.md`、`AGENTS.md`、`GEMINI.md`）

### 更新タイミング

- 技術スタックの変更時（言語、フレームワーク、ツールの変更）
- 設定ファイルの追加・削除時
- プロジェクト要件の変更時（新しい制約、要件、注意事項の追加）

## 作業チェックリスト

### 新規改修時

1. プロジェクトについて詳細に探索し理解すること
2. 作業を行うブランチが適切であること。すでに PR を提出しクローズされたブランチでないこと
3. 最新のリモートブランチに基づいた新規ブランチであること
4. PR がクローズされ、不要となったブランチは削除されていること
5. このプロジェクトではパッケージマネージャーは使用していないため、この手順はスキップ

### コミット・プッシュ前

1. コミットメッセージが Conventional Commits に従っていること。ただし、`<description>` は日本語で記載する
2. コミット内容にセンシティブな情報が含まれていないこと
3. シェルスクリプトの構文エラーがないこと（bash -n でチェック）
4. chezmoi apply --dry-run で動作確認を行い、期待通り動作すること

### プルリクエスト作成前

1. プルリクエストの作成をユーザーから依頼されていること
2. コミット内容にセンシティブな情報が含まれていないこと
3. コンフリクトする恐れがないこと

### プルリクエスト作成後

1. コンフリクトが発生していないこと
2. PR 本文の内容は、ブランチの現在の状態を、今までのこの PR での更新履歴を含むことなく、最新の状態のみ、漏れなく日本語で記載されていること。この PR を見たユーザーが、最終的にどのような変更を含む PR なのかをわかりやすく、細かく記載されていること
3. GitHub Actions CI が存在しないため、この手順はスキップ
4. GitHub Copilot レビュー依頼（`request-review-copilot` コマンドが存在する場合）
5. 10 分以内に投稿される GitHub Copilot レビューへの対応を行うこと。対応したら、レビューコメントそれぞれに対して返信を行うこと。レビュアーに GitHub Copilot がアサインされていない場合はスキップして構わない
6. `/code-review:code-review` によるコードレビューを実施したこと。コードレビュー内容に対しては、**スコアが 50 以上の指摘事項**に対して対応する

## リポジトリ固有

- **chezmoi ベースの構造**: `home/` ディレクトリ配下に chezmoi ソースファイルを配置し、`chezmoi apply` で実環境に適用する
- **暗号化戦略**: age で機密情報を暗号化し、`run_onchange` フックで自動復号化する
  - WakaTime API キー: `encrypted_dot_wakatime.cfg.age`
  - Discord Webhook URL: `.chezmoi.toml.tmpl` でテンプレート管理
- **マルチシェル対応**: bash と zsh の両方に対応し、`.d/` 分割設定で共通管理
- **マルチエージェント対応**: 各 AI エージェント専用のディレクトリを配置（`dot_claude/`、`dot_codex/`、`dot_gemini/`、`dot_copilot/`）
- **テンプレート化**: git ユーザー情報や Discord Webhook は chezmoi テンプレートでマシンごとにカスタマイズ可能
