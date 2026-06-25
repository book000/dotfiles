---
name: deep-review
description: Deep code review of a GitHub PR or the local working diff. Runs independent, scoped sub-agent reviews (CLAUDE.md adherence, bugs, git history, security incl. AI-PR risks, performance, silent failures, type design, tests), scores each finding 0-100 for confidence, reports only findings with score >= 50, and for the user's own PRs auto-fixes, commits, pushes, and updates the PR body.
argument-hint: "[PR number or URL | omit to review the local working diff]"
disable-model-invocation: false
---

# deep-review スキル

PR またはローカル diff に対して独自パイプラインでコードレビューを実施する。
外部プラグインには一切依存しない完全自己完結型スキル。

## モード判定

引数があれば **PR モード**、なければ **ローカル diff モード** で動作する。

- PR モード: 引数から PR 番号または URL を取り出し、`gh pr diff / view` で差分を取得する。autofix 対象。
- ローカル diff モード: `git merge-base origin/$(git symbolic-ref --short HEAD 2>/dev/null || echo main) HEAD` を base として
  `git diff <base>...HEAD` + 作業ツリーの差分を対象とする。レビュー報告のみ行い、autofix・コミットはしない。

## 手順

以下を厳密に順番通りに実行すること。

### ステップ 1: 適格性チェック（PR モードのみ）

Haiku サブエージェントを起動し、PR が以下のいずれかに該当するか確認する。
該当する場合は中止してその理由を報告する:

- PR がクローズ済みまたはドラフト
- 変更が自動生成（Renovate / dependabot 等）または自明で単純
- 自分（akubiusa）がすでにコードレビューコメントを投稿済み

### ステップ 2: CLAUDE.md / rules のパス収集

Haiku サブエージェントを起動し、リポジトリの以下のファイルパスを収集して返させる:

- ルートの `CLAUDE.md`
- 変更ファイルが属するディレクトリ配下の `CLAUDE.md`
- `~/.claude/rules/` 配下のすべての `.md` ファイル

### ステップ 3: 変更サマリの把握

Haiku サブエージェントを起動し、以下を実行させる:

- PR モード: `gh pr view <PR> --json title,body,additions,deletions,files` と `gh pr diff <PR>` で変更の概要を取得して返す。
- ローカル diff モード: `git diff <base>...HEAD --stat` と `git diff <base>...HEAD` でサマリを取得して返す。

### ステップ 4: 並列観点レビュー

**以下の 9 つのサブエージェント（汎用エージェント）を並列起動**する。
各エージェントには差分・変更サマリ・CLAUDE.md ファイルパスリストを渡し、
担当観点での問題を「問題概要 + 根拠 + file:line 引用」形式で返させる。

**全エージェントに共通して渡す指示（偽陽性抑制）:**

以下の典型的な偽陽性は指摘しないこと:
- 変更していない行に存在する既存の問題
- lint / 型チェッカー / CI が自動検出する問題（フォーマット、import エラー、型エラー等）
- 意図的に抑制されている問題（lint ignore コメント等）
- 変更と直接関係のない一般的なコード品質（テスト不足、ドキュメント不足等は、CLAUDE.md に明示された場合を除く）
- 差分が意図的な変更であることが明らかな場合の機能変更の指摘
- 根拠のない推測（必ず `file:line` の根拠を示すこと）

**各エージェントの担当観点:**

- **エージェント a（CLAUDE.md 準拠）**: CLAUDE.md および rules ファイルの内容を実際に読み込んだうえで、
  PR の変更が CLAUDE.md の指示に違反していないか確認する。ただし CLAUDE.md は Claude へのガイダンスであり、
  すべての指示がコードレビューに適用されるわけではないことに注意する。
  CLAUDE.md に明示的に書かれていない問題は指摘しない。

- **エージェント b（バグ・正確性）**: 変更差分を中心に浅くスキャンし、大きなバグのみ報告する。
  変更を超えた広い文脈の読み込みは避ける。ニッチな指摘は行わない。

- **エージェント c（git 履歴・blame）**: 変更されたファイルの git blame・git log を確認し、
  過去の経緯・意図を踏まえた上でのみ問題を報告する。

- **エージェント d（過去 PR コメント）（PR モードのみ）**: 変更されたファイルに触れた過去の PR を
  `gh pr list --state merged` 等で取得し、過去のコメントで同様の指摘がなされていないか確認する。

- **エージェント e（コード内コメントとの整合）**: 変更されたファイルのコード内コメント・docstring を読み、
  変更がコメントの指示に反していないか確認する。

- **エージェント f（セキュリティ）**: 以下の観点で問題を報告する。
  - 入力検証・サニタイズの欠如（XSS、SQL インジェクション等）
  - 認可チェックの欠如または誤った階層への配置
  - シークレット・トークン・API キーのハードコードまたはログ出力
  - **AI エージェント PR 特有の観点:**
    - 未検証の外部入力をプロンプトに混入（プロンプトインジェクション）
    - 過剰なスコープを持つ GitHub トークンの使用
    - モデル出力をバリデーションなしにシェルコマンドとして実行

- **エージェント g（パフォーマンス）**: 以下の観点で問題を報告する。
  - 不要なループ・重複クエリ（N+1 等）
  - ホットパスや背景ジョブへの影響
  - 同期処理で置き換え可能な非同期処理の欠如

- **エージェント h（エラーハンドリング・サイレント障害）**: 以下の観点で問題を報告する。
  - エラーの握り潰し（空の catch ブロック、エラーを無視する `|| true` 等）
  - 不適切なフォールバック（本来エラーにすべきをデフォルト値で隠蔽する等）
  - エラー情報の損失（スタックトレースの破棄等）

- **エージェント i（型設計・テスト）**: 以下の観点で問題を報告する。
  - 型の不変条件が正しく表現されていない（null/undefined が混入可能な型設計等）
  - 新機能や重要なパスに対するテストが存在しない（CLAUDE.md でテストが求められている場合）

### ステップ 5: 確信度スコアリング

ステップ 4 で返ってきた全問題に対し、**問題ごとに Haiku サブエージェントを並列起動**して確信度スコアを付与する。
各エージェントには問題の説明・CLAUDE.md ファイルリスト・PR/diff の内容を渡し、以下のルーブリックを **verbatim** で使用させる:

Score the issue on a scale of 0-100 based on your level of confidence that it is a real issue:

- **0**: Not confident at all. This is a false positive that doesn't stand up to light scrutiny, or is a pre-existing issue.
- **25**: Somewhat confident. This might be a real issue, but may also be a false positive. The agent wasn't able to verify that it's a real issue. If the issue is stylistic, it is one that was not explicitly called out in the relevant CLAUDE.md.
- **50**: Moderately confident. The agent was able to verify this is a real issue, but it might be a nitpick or not happen very often in practice. Relative to the rest of the PR, it's not very important.
- **75**: Highly confident. The agent double checked the issue, and verified that it is very likely it is a real issue that will be hit in practice. The existing approach in the PR is insufficient. The issue is very important and will directly impact the code's functionality, or it is an issue that is directly mentioned in the relevant CLAUDE.md.
- **100**: Absolutely certain. The agent double checked the issue, and confirmed that it is definitely a real issue, that will happen frequently in practice. The evidence directly confirms this.

CLAUDE.md に起因する問題の場合、CLAUDE.md がその問題を具体的に言及しているか二重確認すること。

各エージェントは `Score: <0-100>` の形式でスコアを返すこと（後続フックがこの形式でスコアを抽出する）。

### ステップ 6: スコアフィルタリング

スコア 50 未満の問題をすべて除外する。
残った問題が 0 件の場合、「問題は見つかりませんでした」と報告して中止する。

### ステップ 7: 適格性の再確認（PR モードのみ）

Haiku サブエージェントを起動し、ステップ 1 と同じチェックを再実施する。
該当する場合は中止してその理由を報告する。

### ステップ 8: PR 作者チェック（PR モードのみ）

`gh pr view <PR> --json author` で PR 作者を確認する。

- 作者が `akubiusa` またはユーザーが作成した bot の場合: **ステップ 9（autofix）に進む**。
- Renovate / dependabot / その他の外部コントリビューター: **ステップ 12（結果報告）に進む**（autofix スキップ）。

### ステップ 9: autofix（自分の PR のみ）

スコア 50 以上の問題をすべて修正する。コミットは後で行うため、まず全件修正する。

各問題について:
1. Read ツールで対象ファイルを読む。
2. Edit ツールで問題を修正する。
3. 修正がレビュー指摘に対応していることを確認する。

### ステップ 10: コミット（自分の PR のみ）

すべての修正をコミットする:

1. `git add` で変更ファイルをステージ
2. 以下のコミットメッセージでコミット（Conventional Commits 準拠、description は日本語）:

```
fix: コードレビュー指摘事項を修正

- [修正した問題のリスト]

Co-Authored-By: Claude <noreply@anthropic.com>
Claude-Session: <現在のセッション URL または省略>
```

3. `git push origin <branch>` で push する（SSH を使用）

### ステップ 11: PR 本文更新（自分の PR のみ）

`gh pr edit <PR> --body "..."` で PR 本文を更新し、コードレビュー指摘事項が自動修正済みであることを明記する。

### ステップ 12: 結果報告

**PR モードの場合**: `gh pr comment <PR> --body "..."` でレビュー結果を投稿する。
**ローカル diff モードの場合**: レビュー結果をユーザーに直接提示する。

#### 出力フォーマット

問題が見つかった場合（autofix 実施済み）:

```
### Deep Review

Found X issues and **automatically fixed them** in commit [sha]:

1. <問題の簡潔な説明>

Score: <スコア>

<github.com/<owner>/<repo>/blob/<full_sha>/<path>#L<start>-L<end> 形式のリンク>

**Fixed**: <修正内容の説明>

---

🤖 Generated with [Claude Code](https://claude.ai/code)

<sub>- If this code review was useful, please react with 👍. Otherwise, react with 👎.</sub>
```

問題が見つかった場合（他者の PR = autofix なし）:

```
### Deep Review

Found X issues:

1. <問題の簡潔な説明>

Score: <スコア>

<github.com/<owner>/<repo>/blob/<full_sha>/<path>#L<start>-L<end> 形式のリンク>

---

🤖 Generated with [Claude Code](https://claude.ai/code)

<sub>- If this code review was useful, please react with 👍. Otherwise, react with 👎.</sub>
```

問題が見つからなかった場合:

```
### Deep Review

No issues found. Checked for bugs, CLAUDE.md compliance, security (incl. AI-PR risks), performance, error handling, silent failures, type design, and test coverage.

🤖 Generated with [Claude Code](https://claude.ai/code)
```

#### フォーマット上の注意事項

- GitHub のコードリンクは必ず `full SHA + #L<行番号>` 形式で記述する（`$(git rev-parse HEAD)` の埋め込みは不可）。
  正しい例: `https://github.com/book000/dotfiles/blob/1d54823877c4de72b2316a64032a54afc404e619/home/dot_claude/SKILL.md#L10-L15`
- 絵文字は使用しない（最終サマリの 👍/👎 を除く）。
- 各問題に `Score: <数値>` を必ず含める（Stop フックがこの形式でスコアを抽出するため必須）。
- 指摘はコードと CLAUDE.md の両方を引用・リンクして根拠を示す。
