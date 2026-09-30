## 基本方針

- ユーザーの明示的な承認なしに、フック・設定・PR を変更しない。PR は明示的な指示があるまでマージしない。
- 前提・仮定・不確実性を明示し、実装を危険にする曖昧さがある場合は質問する。外部仕様は一次情報で確認する。
- 最終回答は日本語、途中経過は簡潔な英語で記載する。コードコメントはリポジトリの指示に従い、未指定なら日本語、エラーメッセージは英語にする。日本語と英数字の間には半角スペースを入れる。
- 判断記録はローカルの Markdown ファイルではなく、GitHub Issue コメントまたは PR 本文に残す。
- 読み書きの対象が Codex 自身の指示・skill・hook・settings である場合は、影響範囲を分離するためサブエージェントに委譲する。chezmoi 管理対象は展開先ではなく `home/` 配下のソースを更新する。
- 複数段階にわたり、または長時間続く作業で compaction が見込まれる場合は、会話が長くなる前に GitHub Issue コメントへ再開用 checkpoint を記録する。些細ですぐ完了する作業では不要。checkpoint には目標と受け入れ条件、決定・前提、branch と worktree の状態および変更 path、完了した作業と検証結果、未完了事項・blocker、次に実行する具体的な action を簡潔に含め、secret や生ログは含めない。正確な compaction 時点を推測せず、重要な状態を失う前に記録する。compaction 後は checkpoint を読み直し、続行前に現在の repository と GitHub の状態を確認して、古くなった記述をそのまま事実として扱わない。Issue に紐付かない作業ではローカル Markdown を checkpoint として作らず、同様の要点を compaction 前に簡潔な assistant の会話メッセージとして記録する。compaction 後はそのメッセージを読み直してから続行し、repository の状態を再確認する。
- `command_relay_mcp` は使用しない。リモートマシンへの接続には SSH を試し、GitHub の参照・操作には MCP ではなく `gh` CLI を使う。利用可能なエイリアスは環境ごとに異なるため、検出できると仮定しない。

## Git と PR

- ブランチは Conventional Branch の短縮形、コミットは Conventional Commits を使う。説明文の言語はリポジトリの指示に従い、未指定なら日本語にする。
- SSH で push する。`GH_CONFIG_DIR`、`GIT_*`、`GIT_SSH_COMMAND` は許可なく変更せず、Git の username/email も変更しない。Renovate が作成した PR にはコミットしない。
- SSH で `Bad owner or permissions on ...ssh_config...` が発生したら、`id` と `stat -L` で対象ファイルおよび symlink の実体の所有者・権限を確認し、`ssh -G <host>` で設定読み込み段階の失敗かを切り分ける。Codex sandbox が原因とは証拠なしに断定しない。`ssh -F "$HOME/.ssh/config"` は system-wide `/etc/ssh/ssh_config` を読み飛ばすため、`-F /dev/null` / `none` を使わない。per-user config が対象 host / alias を解決し、必要な system-wide alias・known-host・crypto policy 等が同等に設定されている、または不要と確認できる場合だけ、`ssh -F "$HOME/.ssh/config" -G <host>` と読み取り専用の接続確認を行う。確認できない、または検証が失敗する場合は設定を迂回せず、証拠とエラーを報告する。Git で同じ回避が必要かつ条件を確認できた場合は `git -c core.sshCommand="ssh -F \"$HOME/.ssh/config\"" <operation>` でそのコマンドに限り適用する。環境変数、永続的な SSH / Git 設定、ファイル所有者・権限、sandbox mode は変更しない。
- 実装前に、リポジトリ構成、作業ブランチ、最新のリモート既定ブランチ、不要なローカルブランチ、必要な依存関係を確認する。調査目的の GitHub リポジトリは一時ディレクトリへ clone する。
- コミット前に、秘密情報、lint/format エラー、必要な検証、期待どおりの動作を確認する。
- PR 作成前に、ユーザーの依頼、秘密情報、競合リスク、変更内容に応じたローカルコードレビューを確認する。PR 作成先は `gh-pr-target-repo.sh` を優先し、GitHub の `upstream` remote があればそれを既定にする。
- PR 本文には現在の状態のみを記載し、更新履歴を列挙しない。PR 作成前の monitor preflight は非変更で、起動能力または選択する fallback だけを確認する。canonical PR URL を取得するまで pane の登録、state/window の作成、watcher の起動をしない。`gh pr create` の前に、PR 作成後に開始できる永続的な terminal または `$resume-pr-monitor <PR URL>` の fallback を選択して維持する。永続的な terminal または resume fallback を選択できない場合は PR を作成せず停止する。PR 作成直後は `$pr-health-monitor` が canonical URL を取得して state を初期化し、nonce/register-pane、`watch-pr.sh start` の順に実行する。`start` は tmux window を作成しただけでは成功にせず、live watcher lock と同じ PID の state を bounded interval で確認してから active とする。確認できない場合は作成した window を停止して `foreground_required` と watcher PID の clear を記録する。monitor が失敗した場合は incomplete/unmonitored、canonical PR URL、失敗した stage、その failure を示す fresh evidence、`$resume-pr-monitor <canonical PR URL>` の正確な recovery command を報告し、complete、monitoring、または deployment-ready と報告しない。tmux 内の Codex は登録済み pane に専用 monitor window から固定の `$resume-pr-monitor` prompt を配送できる。ready state と配送の間に user input が始まる race は既知の制約である。watcher は GitHub の PR コメントとレビューを actor を問わず検知し、review feedback event を `$handle-pr-reviews` へ送る。watcher 自体は Git/GitHub action を実行しない。
- PR 作成直前の最終ゲートは fail-closed で、HEAD、index、worktree の tracked、staged、untracked と evidence ID を含む snapshot を 1 回記録して全 substep で使う。各 substep 後と final evidence 確認後かつ commit/PR 作成直前に同じ snapshot と比較する。差分、status、evidence のいずれかが変われば最終ゲート全体を最初からやり直す。commit、PR 作成、deployment-ready/deployed を含む deployment assertion は、この reviewed snapshot に対して final evidence を確認した直後に限って行う。snapshot を再取得・更新してはならず、差分、status、evidence のいずれかが変われば最終ゲート全体を最初からやり直す。50 以上、P1、P2 の未解決指摘、検証失敗、secret、意図しない差分があれば停止する。
- 複数 Issue を 1 つの PR で扱う場合は、すべての Issue が一意、open、target repository 所属であることを検証する。Issue ごとに scope と acceptance criteria を確認し、必要な文書、review evidence、closing keyword を個別に用意・確認する。全 Issue の確認結果を集約し、すべてが aggregate 最終ゲートを通過するまで PR を作成しない。PR 本文の `Closes #<issue>` は、closing keyword を含み、検証済みの Issue だけを正確に列挙する。

## 実装と検証

- 既存の構成・命名に合わせ、コードで明らかな内容をコメントで重複させない。コメントは理由・制約・将来壊れうる前提だけに使い、変更履歴を残さない。
- リポジトリ構成・利用手順・テスト・セキュリティ方針を変える場合は、README、プロジェクトの指示、Copilot 向け指示の更新要否を確認する。
- 変更に対応する syntax、unit、integration テストを実行する。通知・フック・helper を変更または削除した場合は、テスト内の参照も確認する。
- chezmoi では `executable_` 接頭辞が展開時に除去される。設定からスクリプトを参照するときは、展開後の名前を使う。

## 追加ガイダンス

- 外部ライブラリやフレームワークの API、設定、互換性、非推奨化、バージョン差異を扱うときは、プロジェクトの lockfile 等から対象バージョンを特定し、一次情報で確認する。特定できなければ不明と明記して分岐を示す。
- ユーザーへの確認は `request_user_input` ツールを使う。要件が複数に解釈できるときは、勝手に選ばない。
- Markdown の段落途中で手動改行しない。箇条書き、表、見出し、コードブロックはこの制約の対象外とする。
- GitHub Issue に紐付く仕様・計画・調査の成果物は、秘密情報を確認した上で Issue コメントへ投稿し、投稿後は URL のみを報告する。別々の文書は別コメントにし、更新時はそのコメント ID を指定する。Issue と無関係な文書の保存先は、利用可能な skill またはユーザーの指示に従う。
- `docs/superpowers/specs/` または `docs/superpowers/plans/` を作成・更新した後、ユーザーへ提示する前に `spec_reviewer` または `plan_reviewer` agent にレビューと修正を依頼する。これらのローカル成果物が ignore 対象なら force-add しない。

変更対象に応じて、以下の reference を先に読む。

| 対象 | Reference |
| --- | --- |
| 共通のコード品質、秘密情報、破壊的操作、依存関係、入力処理 | `~/.codex/references/coding-and-security.md` |
| TypeScript / JavaScript | `~/.codex/references/typescript-javascript.md` |
| Python、Shell、Dockerfile | `~/.codex/references/python-shell-docker.md` |
| C#、`.csproj`、`.sln`、`.editorconfig` | `~/.codex/references/csharp.md` |
| GitHub Actions workflow | `~/.codex/references/github-actions.md` |
| GitHub Issue 文書、Jira、GlitchTip、agent 委譲 | `~/.codex/references/workflow.md` |

## Codex Skills

Codex CLI では任意の custom slash command ではなく、skill でコマンド相当のワークフローを提供する。Codex は repo / user / admin / system scope の skill を読み込む。この dotfiles は user scope の `~/.agents/skills` を管理する。

- この dotfiles が管理する skill は `~/.agents/skills` に配置する。
- 明示的な実行には `$` で skill を指定する。
- `$issue-pr`: GitHub Issue から実装、PR 作成、PR 後フロー開始までを行う。
- `$ticket-pr`: Jira チケットから実装、PR 作成、PR 後フロー開始までを行う。
- `$glitchtip-pr`: GlitchTip issue から実装、PR 作成、明示的な verified Resolve までを行う。
- `$pr-health-monitor`: PR の CI、競合、本文、Codex/Copilot レビューを確認し、XDG state の観測専用 watcher を開始する。
- `$resume-pr-monitor`: pending PR monitor event を fresh GitHub state で再確認し、成功した後処理だけを acknowledge する。
- `$handle-pr-reviews`: 未解決レビュースレッドを修正、返信、resolve まで処理する。
- `$deep-review` / `$lite-review`: 変更を複数観点または重点観点でレビューする。
- `$issue-pr-deep` / `$issue-pr-lite`: 規模に応じて GitHub Issue から PR を作成する。
- `$glitchtip-pr-deep` / `$glitchtip-pr-lite`: 規模に応じて GlitchTip issue から PR を作成する。
- `$pr-cleanup`: マージ済み PR の後処理を行う。
- `$wait-for-copilot-review` / `$wait-for-pr-close`: PR のレビューまたはクローズを durable event として監視する。
- `$check-container-status`: Docker Compose プロジェクトの状態を確認する。
- `$agents-md-maintainer`: `AGENTS.md` のエージェント向けガイダンスを保守する。
- `$rtk`: RTK の利用手順を参照する。
- `$trilium`: Trilium 連携の手順を実行する。
- `$i-have-adhd`: ADHD の読み手向けに、行動優先・番号付き手順・進捗明示の出力へ切り替える。
- skill を更新しても一覧へ反映されない場合は Codex を再起動する。
