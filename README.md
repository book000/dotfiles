# book000/dotfiles

<!-- CI verification test -->

このリポジトリは、chezmoi を使用して dotfiles と AI エージェント設定を管理するものです。

## インストール方法

### 推奨: 3 ステップインストール（より安全）

```bash
# ステップ 1: スクリプトをダウンロード
curl -fsSL https://raw.githubusercontent.com/book000/dotfiles/master/install.sh -o /tmp/install.sh

# ステップ 2: スクリプトを確認（推奨）
less /tmp/install.sh

# ステップ 3: 実行
bash /tmp/install.sh
```

### ワンライナー（自己責任）

```bash
curl -fsSL https://raw.githubusercontent.com/book000/dotfiles/master/install.sh | bash
```

### 非対話モード

CI や自動化で使用する場合は、`NO_INTERACTIVE=1` を設定してください:

```bash
NO_INTERACTIVE=1 bash /tmp/install.sh
```

非対話モードでは、以下の設定がスキップまたはデフォルト値で作成されます:

- `.gitconfig.local`: `.gitconfig.local.example` からコピー（後で手動編集が必要）
- `.env`: `chezmoi apply` 前に `.env.example` から自動コピー（作成後に手動編集が必要）
- mkwork の `work_root`: デフォルトで `~/work` に設定

## インストール後の設定

インストール完了後、以下のファイルを編集してください:

### 1. .gitconfig.local

Git のユーザー名とメールアドレスを設定します:

```bash
vim ~/.gitconfig.local
```

### 2. .env

Discord Webhook URL などの環境変数を設定します:

```bash
vim ~/.env
```

### 3. PATH の設定

`~/.local/bin` が PATH に含まれていない場合は、シェル設定ファイル（`~/.bashrc` または `~/.zshrc`）に以下を追加してください:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

## サポート環境

- **OS**: Ubuntu, Debian
- **アーキテクチャ**: x86_64 (amd64), aarch64/arm64

macOS と Windows は現在サポートされていません。

## セキュリティに関する注意事項

`curl | bash` 方式には以下のリスクがあります:

- **部分的なコンテンツ実行**: TCP 接続が途中で切れた場合、不完全なスクリプトが実行される可能性があります
- **サーバー側のコンテンツ切り替え**: User-Agent を検出して、異なるコンテンツを配信される可能性があります

より安全にインストールするには、3 ステップインストール（ダウンロード、確認、実行）を推奨します。

## Claude Code 通知機能

Claude Code がユーザー操作を必要とする場合に、Discord Webhook を使用して通知する機能が実装されています。

### 通知されるイベント

1. **セッション完了通知 (Stop hook)**
   - Claude が処理を完了した際に通知
   - 最新 5 件の会話履歴を含む

2. **権限リクエスト通知 (PermissionRequest hook)**
   - Claude がツールの使用許可を求めている際に通知
   - リクエストされたツール名と入力パラメータを含む

3. **ユーザー操作必要通知 (Notification hook)**
   - 以下のタイプの通知が Discord に送信されます:
     - `permission_prompt`: 権限プロンプトが表示された場合
     - `idle_prompt`: Claude がアイドル状態の場合

### 通知抑制機能

ユーザーがターミナルを監視し即座に対応している場合、Discord 通知は不要です。そのため、以下の仕組みで通知を抑制します:

- **60 秒の待機時間**: 通知イベントが発生してから 60 秒待機してから通知を送信
- **新規プロンプトによるキャンセル**: 待機中にユーザーが新しいプロンプトを送信した場合、通知をキャンセル
- **UserPromptSubmit hook**: プロンプト送信を検出し、待機中の通知をキャンセル

この機能により、ユーザーが Claude Code を監視しながら対話している場合は通知が送信されず、不要な通知を削減できます。

### 設定方法

通知機能を有効にするには、`~/.env` ファイルに以下の環境変数を設定してください:

```bash
# Discord Webhook URL (必須)
DISCORD_CLAUDE_WEBHOOK=https://discord.com/api/webhooks/...

# メンション先のユーザー ID (オプション)
DISCORD_CLAUDE_MENTION_USER_ID=123456789012345678
```

## Claude Code コマンド

### issue-pr

GitHub の issue を確認し、対応のためのブランチを作成して PR を作成する Claude Code コマンドです。

```
/issue-pr <issue_number>
```

- issue のタイトルから適切なブランチ名を自動生成します
- デフォルトブランチ（master または main）から最新の状態でブランチを作成します
- issue の内容に基づいて対応を行い、PR を作成します

## code-review プラグインのカスタマイズ

Claude Code の `/code-review:code-review` コマンドは、デフォルトでスコア 80 以上の指摘のみを報告しますが、このリポジトリでは閾値を 50 に変更しています。

### 仕組み

1. **パッチファイル**: `home/dot_claude/patches/code-review-threshold.patch` に閾値変更パッチを配置
2. **自動適用**: `chezmoi apply` 時に `.chezmoiscripts/run_after_apply-code-review-patch.sh.tmpl` が毎回実行され、パッチを自動適用
3. **キャッシュクリア**: パッチファイルが変更されると、`dot_claude/.chezmoiscripts/run_onchange_after_clear-plugin-cache.sh.tmpl` が自動実行され、プラグインキャッシュ (`~/.claude/plugins/cache/`) をクリア
4. **冪等性**: 既にパッチが適用されている場合はスキップ（何度実行しても安全）

### 閾値の変更方法

閾値を変更したい場合は、`home/dot_claude/patches/code-review-threshold.patch` を編集してください。

```diff
-6. Filter out any issues with a score less than 80. If there are no issues that meet this criteria, do not proceed.
+6. Filter out any issues with a score less than 50. If there are no issues that meet this criteria, do not proceed.
```

変更後、`chezmoi apply` を実行すると新しい閾値が適用されます（スクリプトは毎回実行され、冪等性があります）。

### 注意事項

- code-review プラグインの構造が変更された場合、パッチの適用に失敗する可能性があります
- その場合は、パッチファイルを手動で更新する必要があります

<!-- CI verification test -->