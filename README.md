# book000/dotfiles

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

**注意**: Plan Mode（`/plan`）が有効な状態では実行できません。`issue-pr` skill 側で Plan Mode を検知すると即座に停止するため、実行前に Plan Mode を終了してください。

このコマンドは以下の流れで動作します：

1. **Worktree の作成**: `EnterWorktree` でこの Issue 専用の作業ツリーを作成
2. **Issue 内容の取得**: `gh issue view` で Issue のタイトル・本文・コメントを取得
3. **spec（設計）の作成**: `superpowers:brainstorming` により要件を対話的に確認し、spec を作成
4. **spec のレビュー**: sub-agent による自動レビューを実施
5. **spec の Confluence アップロード**: レビュー後の spec を Confluence にアップロード
6. **spec の承認**: `AskUserQuestion` でユーザーに承認を求める
7. **plan（実装計画）の作成**: `superpowers:writing-plans` により plan を作成
8. **plan のレビュー・Confluence アップロード・承認**: spec と同様の流れを plan にも適用
9. **Issue へのコメント投稿**: spec/plan の Confluence URL を Issue にコメント
10. **ブランチ作成・実装**: Conventional Branch 名でブランチを作成し、plan を実行
11. **検証・ローカルコードレビュー**: 動作確認と `/deep-review` を実施
12. **PR 作成**: PR を作成し、CI 確認・Copilot レビュー対応まで行う

**使用例:**

```bash
# Issue #49 に対応
/issue-pr 49

# Worktree 作成 → spec/plan 作成・レビュー・承認 → ブランチ作成 → 実装 → PR 作成 → CI 確認 → Copilot レビュー対応
```

### ticket-pr

Jira チケットを確認し、対応のためのブランチを作成して PR を作成する Claude Code スキルです。
`issue-pr` の Jira チケット版です。Jira MCP を使用してチケット情報を取得します。

```
/ticket-pr <ticket_key_or_url>
```

引数には Jira チケットキー（例: `PROJECT-123`）または URL（例: `https://company.atlassian.net/browse/PROJECT-123`）を指定します。

#### Jira 課題タイプとブランチタイプの対応

| Jira 課題タイプ | ブランチタイプ |
|---|---|
| Epic / Story / Task / New Feature / Improvement | `feat` |
| Bug | `fix` |
| Documentation | `docs` |
| Refactoring / Technical Debt | `refactor` |
| Sub-task | 親チケットに準拠、不明なら `feat` |

#### プランモードで実行した場合

プランモード（`/plan` コマンドで起動）で実行すると、以下の作業を行います：

1. **Jira チケット情報の取得**: Jira MCP でチケット内容を取得
2. **ユーザーへの質問** (不明点がある場合のみ): 不明点や仕様の確認を対話的に質問
3. **外部仕様の確認**: 必要に応じて外部依存や最新仕様を確認
4. **要件定義書の作成**: 詳細な要件定義書を作成
5. **Jira チケットへのコメント投稿**: 要件定義書を Jira チケットにコメントとして投稿
6. **プランファイルへの記載**: 実装計画をプランファイルに記載
7. **ExitPlanMode の実行**: プランモードを終了し、ユーザーの承認を待つ

#### 実行モードで実行した場合

1. Jira チケット情報を MCP で取得
2. チケットタイプからブランチタイプを決定しブランチを作成
3. 実装を行い PR を作成（PR に Jira への言及は含めない）
4. Jira チケットに PR URL を含む完了コメントを投稿
5. `/pr-health-monitor` でポスト PR フローを実行

**使用例:**

```bash
# チケットキーで指定
/ticket-pr PROJECT-123

# URL で指定
/ticket-pr https://company.atlassian.net/browse/PROJECT-123
```

## `/deep-review` スキル

外部プラグインに依存しない自前のコードレビュースキル。
`home/dot_claude/skills/deep-review/SKILL.md` として管理され、`chezmoi apply` で `~/.claude/skills/deep-review/SKILL.md` にデプロイされる。

### 使い方

```bash
# PR をレビューする
/deep-review 123
/deep-review https://github.com/owner/repo/pull/123

# ローカル diff をレビューする（引数なし）
/deep-review
```

### 特徴

- **外部依存なし**: `code-review@claude-plugins-official` や `pr-review-toolkit@claude-plugins-official` を一切使用しない
- **独自パイプライン**: 独立したサブエージェントを並列起動して観点別にレビューし、確信度スコア 0-100 でフィルタリング（スコア 50 未満は除外）
- **PR/ローカル diff 両対応**: 引数ありで PR モード、引数なしでローカル diff モード
- **自動修正（自分の PR のみ）**: スコア 50 以上の指摘を自動修正 → コミット → push → PR 本文更新
- **偽陽性抑制**: 各エージェントに「無視すべきもの」を明示して精度を確保

### レビュー観点

固定レビュアー 9 件は `home/dot_claude/skills/deep-review/reviewers/*.md` に 1 ファイル 1 観点で定義されており、`chezmoi apply` で `~/.claude/skills/deep-review/reviewers/*.md` にデプロイされる。

| 観点 | 内容 | 定義ファイル |
|---|---|---|
| CLAUDE.md 準拠 | CLAUDE.md / rules の指示との整合性 | `reviewers/a-claude-md-compliance.md` |
| バグ・正確性 | 変更差分中心の大きなバグの検出 | `reviewers/b-bugs-correctness.md` |
| git 履歴 | blame・log を踏まえた問題 | `reviewers/c-git-history.md` |
| 過去 PR コメント | 同ファイルへの過去の指摘との照合（PR モードのみ）| `reviewers/d-past-pr-comments.md` |
| コード内コメント整合 | docstring・コメントの指示との整合 | `reviewers/e-code-comment-quality.md` |
| セキュリティ | 入力検証・認可・シークレット漏洩・AI-PR 固有リスク | `reviewers/f-security.md` |
| パフォーマンス | 不要ループ・N+1・ホットパスへの影響 | `reviewers/g-performance.md` |
| サイレント障害 | エラー握り潰し・不適切なフォールバック | `reviewers/h-error-handling.md` |
| 型設計・テスト | 不変条件の表現・重要パスのテスト欠如 | `reviewers/i-type-design-tests.md` |

### プロジェクト固有レビュアーの追加

`deep-review` を使う各リポジトリは、固定 9 観点に加えて自リポジトリ独自のレビュー観点を追加できる。レビュー対象リポジトリのルート（`git rev-parse --show-toplevel` で解決）に `.claude/deep-review-reviewers/*.md` を配置すると、`/deep-review` 実行時に自動検出されて既存レビュアーと並列に起動される。

```markdown
---
name: my-custom-rule
title: 独自の観点
applies_to: all        # all | pr-only（省略時は all）
---

## Scope

このプロジェクト固有のレビュー観点をここに記述する。
```

追加数に厳密な上限はないが、目安として +3 程度を推奨する（4 件以上検出された場合は `/deep-review` 実行時に一言案内が表示されるのみで、処理は継続する）。

### 強制対応フック

`~/.claude/hooks/deep-review-immediate-fix.sh`（PostToolUse）と
`~/.claude/hooks/deep-review-require-fixes.sh`（Stop）が設定されており、
スコア 50 以上の指摘が未対応の場合は Claude の処理を一時ブロックして対応を促す。

これらのフックは公式フック契約（stdin JSON + `decision/reason` 出力）に準拠している。
