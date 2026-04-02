## tmux IPC (エージェント間通信)

tmux セッション内で動作する AI エージェント間でファイルベース IPC を使って通信できる。

### 仕組み

- メッセージは `/tmp/tmux-ipc/{session_id}/inbox/` に JSON ファイルとして保存される
- `SessionStart` / `UserPromptSubmit` / `PostToolUse` フックが inbox をスキャンし、受信メッセージを `additionalContext` として自動注入する
- セッション ID は `{tmux_session_name}.{pane_id}` 形式 (例: `main.%0`)

### 主なコマンド

| コマンド | 説明 |
|---|---|
| `ipc-register [agent_type]` | 現在のセッションを登録する |
| `ipc-send <to_session_id> <body> [ttl]` | 指定セッションにメッセージを送信する |
| `ipc-receive` | inbox のメッセージを手動で受信する |
| `ipc-list` | 登録済みセッション一覧を表示する |
| `ipc-cleanup` | 期限切れメッセージをクリーンアップする |

### IPC メッセージを受信したら

`additionalContext` に IPC メッセージが含まれている場合、内容を確認して必要に応じて対応すること。
送信元エージェントへの返信が必要な場合は `ipc-send` を使用する。

## Codex Skills

Codex CLI では、Claude Code のような任意の custom slash command を追加せず、skill を使ってコマンド相当のワークフローを提供する。
Codex は repo / user / admin / system scope の skill を読み込めるが、この dotfiles では user scope の `~/.agents/skills` を管理する。

2026-04-01 時点の OpenAI 公式 docs では、Codex hook は Windows で無効化されている。
この dotfiles の hook ベース機能は Linux / WSL など、hook が有効な環境で動かす前提とする。

- この dotfiles が管理する skill は `~/.agents/skills` に配置する
- 明示的に呼び出す場合は `$` で skill を指定する
- この dotfiles では以下の skill を提供する
  - `$issue-pr`
  - `$pr-health-monitor`
  - `$handle-pr-reviews`
- skill を更新したのに一覧へ反映されない場合は Codex を再起動する

## 基本的なルール

- 前提・仮定・不確実性を明示すること。仮定を事実のように扱ってはならない
- **判断記録の保存先**: Markdown ファイルに書き込んだり Git 管理したりはしない。Issue コメントや PR 本文に記載すること

## 言語

- 最終的なユーザへの回答は日本語で行なってください。途中経過は、コンテキスト削減のため主要・重要なところ以外は英語で説明します。
- コード内のコメントは、日本語で記載してください。エラーメッセージなどは、原則英語で記載します。

## 環境のルール

- Git コミットの作成時は、[Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/) に従わなければなりません。ただし、`<description>` は日本語で記載します。
- ブランチを作成するときは、[Conventional Branch](https://conventional-branch.github.io) に従わなければなりません。ただし、`<type>` は短縮形 (feat, fix) で記載します。
- PR の作成先は `gh-pr-target-repo.sh` の結果を優先すること。`upstream` remote が存在する場合は upstream を既定の PR 作成先とする
- GitHub リポジトリを調査のために参照する場合、テンポラリディレクトリに git clone して、そこでコード検索してください。
- Windows 環境ですが、Git Bash で動作しています。bash コマンドを使用してください。PowerShell コマンドを使用する場合は、明示的に `powershell -Command ...` か `pwsh -Command ...` を使用してください。
- AGENTS.md の内容は適宜更新しなければなりません。
- このプロジェクトでは Serena が使用できます。
- Renovate が作成した既存のプルリクエストに対して、追加コミットや更新を行ってはなりません。

## Git Worktree について

プロジェクトによっては、Git Worktree を採用している場合があります。

Git Worktree のディレクトリ構成は、以下でなければなりません。  
新規ブランチを作成する場合は、ブランチ作成後に Git Worktree を新規作成してください。

```text
.bare/
<ブランチ名>
```

例は以下の通りです。

```text
.bare/              # bare リポジトリ（隠しディレクトリ）
master/             # master ブランチの worktree
develop/            # develop ブランチの worktree
feature/
  x/                # feature/x ブランチの worktree
```

## コード改修時のルール

- 日本語と英数字の間には、半角スペースを挿入しなければなりません
- 既存のエラーメッセージで、先頭に絵文字がある場合は、全体でエラーメッセージに絵文字を設定してください。絵文字はエラーメッセージに即した一文字の絵文字である必要があります。
- TypeScript プロジェクトにおいて、skipLibCheckを有効にして回避することは絶対にしてはなりません
- 関数やインターフェースには、docstring (jsdoc など) を記載・更新してください。日本語で記載する必要があります。

## 必ず実施すること

以下の内容については、Todo ツールを使用し、漏らさずすべてを実施してください。

### 新規改修時

新規改修を行う前に、以下を必ず確認しなければなりません

1. プロジェクトについて詳細に探索し理解すること
2. 作業を行うブランチが適切であること。すでに PR を提出しクローズされたブランチでないこと
3. 最新のリモートブランチに基づいた新規ブランチであること
4. PR がクローズされ、不要となったブランチは削除されていること
5. プロジェクトで指定されたパッケージマネージャにより、依存パッケージをインストールしたこと

### コミット・プッシュする前

コミット・プッシュする前に、以下を必ず確認しなければなりません

1. コミットメッセージが [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/) に従っていること。ただし、`<description>` は日本語で記載します。
2. コミット内容にセンシティブな情報が含まれていないこと
3. Lint / Format エラーが発生しないこと
4. 動作確認を行い、期待通り動作すること

### プルリクエストを作成する前

プルリクエストを作成する前に、以下を必ず確認しなければなりません

1. プルリクエストの作成をユーザーから依頼されていること
2. コミット内容にセンシティブな情報が含まれていないこと
3. コンフリクトする恐れが無いこと

### プルリクエストを作成したあと

プルリクエストを作成したあとは、以下を必ず実施しなければなりません。PR 作成後のプッシュ時に毎回実施してください。  
時間がかかる処理が多いため、可能なら subagent や並列実行を使用してください。

1. コンフリクトが発生していないこと
2. PR本文の内容は、ブランチの現在の状態を、今までのこのPRでの更新履歴を含むことなく、最新の状態のみ、漏れなく日本語で記載されていること。このPRを見たユーザーが、最終的にどのような変更を含むPRなのかをわかりやすく、細かく記載されていること
3. `gh pr checks <PR ID> --watch` で GitHub Actions CI を待ち、その結果がエラーとなっていないこと。成功している場合でも、ログを確認し、誤って成功扱いになっていないこと。もし GitHub Actions が動作しない場合は、ローカルで CI と同等のテストを行い、CI が成功することを保証しなければなりません。
4. `request-review-copilot` コマンドが存在する場合、`request-review-copilot https://github.com/$OWNER/$REPO/pull/$PR_NUMBER` で GitHub Copilot へレビューを依頼すること。レビュー依頼は自動で行われる場合もあるし、制約により `request-review-copilot` を実行しても GitHub Copilot がレビューしないケースがある
5. `~/.agents/skills/pr-health-monitor/scripts/wait-for-copilot-review.sh <PR_NUMBER> &` で 10 分以上の待機が必要な監視をバックグラウンド化するか、`$pr-health-monitor <PR_NUMBER_OR_URL>` を使用すること
6. 投稿された GitHub Copilot レビューへの対応を行うこと。対応したら、レビューコメントそれぞれに対して返信を行うこと。レビュアーに GitHub Copilot がアサインされていない場合はスキップして構わない
