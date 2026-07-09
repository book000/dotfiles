---
name: claude-md-maintainer
description: Analyze a project's CLAUDE.md against curated best practices plus a live web-search delta, then either rewrite it wholesale or apply targeted edits depending on how far it has drifted. Also creates a CLAUDE.md from scratch when none exists.
argument-hint: "[directory | omit to use the current directory]"
disable-model-invocation: true
---

# claude-md-maintainer skill

任意のプロジェクトの `CLAUDE.md` を、静的なベストプラクティス集（`references/best-practices.md`）と実行時の Web 検索による最新動向の差分を踏まえて分析し、既存内容との乖離度に応じて全面書き直しまたは部分修正を行う。既存の `CLAUDE.md` がない場合は新規作成する。

`disable-model-invocation: true` により、既存 CLAUDE.md についての通常の会話中に誤って自動起動しない。明示的な `/claude-md-maintainer` 実行時のみ動作する。

## 対象ディレクトリの決定

引数が指定されていればそのディレクトリを対象とする。省略時はカレントディレクトリを対象とする。

```bash
TARGET_DIR="${1:-.}"
if [ ! -d "$TARGET_DIR" ]; then
  echo "ERROR: directory not found: $TARGET_DIR" >&2
  exit 1
fi
if [ ! -r "$TARGET_DIR" ]; then
  echo "ERROR: directory not readable: $TARGET_DIR" >&2
  exit 1
fi
```

対象ディレクトリが存在しない、または読み取り不可の場合はエラーを報告して中断する。

## Step 1: 対象プロジェクトの探索

- `$TARGET_DIR/CLAUDE.md` が存在するか確認し、あれば全文を `Read` する。
- プロジェクトの言語・フレームワークを、`package.json` / `pyproject.toml` / `Cargo.toml` / `go.mod` 等の存在で判定する。
- ディレクトリ構成、README、既存のテスト・Lint コマンド（`package.json` の `scripts` 等）を把握する。
- git 管理下か確認する:

```bash
cd "$TARGET_DIR" && git rev-parse --is-inside-work-tree >/dev/null 2>&1
```

管理下でなければ、「事後の差分確認ができない」旨を警告として記録し、続行する（書き込み自体は行う）。

## Step 2: 静的リファレンスの読み込み

`~/.claude/skills/claude-md-maintainer/references/best-practices.md` を `Read` する。

## Step 3: 最新動向のライブ検索

WebSearch で以下のようなクエリを実行し、`references/best-practices.md` の内容に対する **差分**（新たに登場した推奨事項、非推奨になった慣習、公式ドキュメントの更新など）のみを抽出する:

- `CLAUDE.md best practices <現在の年>`
- `Claude Code memory files guide`
- `Anthropic Claude Code CLAUDE.md documentation`

検索結果が有望であれば WebFetch で該当ページの詳細を取得する。

検索が失敗した場合（ネットワークエラー等）は、静的リファレンスのみで Step 4 以降を続行し、その旨を最終報告（Step 6）に含める。

## Step 4: プロジェクト固有情報の抽出

既存の `CLAUDE.md`（あれば）から、プロジェクト固有で失ってはいけない情報を抽出する:

- 具体的なコマンド（ビルド・テスト・デプロイ等）
- 既知の落とし穴・注意事項
- リポジトリ構造の事実
- チーム固有の運用ルール

Step 1 の探索結果と突き合わせ、既存記述が実態と乖離していないか（コマンドが実際に `package.json` 等に存在するか等）も確認する。乖離している記述（存在しないコマンドへの言及等）は Step 5 の判断材料として記録する。

## Step 5: 乖離度の評価と反映方針の決定

Step 2〜4 の結果をもとに、既存 `CLAUDE.md` とベストプラクティスとの乖離度を評価する。

- **乖離が大きい**場合（以下のいずれかに該当）→ 全面的に書き直す。
  - `references/best-practices.md` の「書くべきカテゴリ」のうち該当するもの（プロジェクトの性質上不要なカテゴリを除く）が半数以上欠落している。
  - 見出し構成が崩れており、カテゴリ単位で整理されていない。
  - 実態と乖離した記述（存在しないコマンド・廃止されたファイルへの言及等）が複数箇所ある。
- **乖離が小さい**場合（該当カテゴリが概ね揃っており、部分的な追記・訂正で十分）→ 該当箇所のみを編集する。
- 既存 `CLAUDE.md` が存在しない場合 → 新規作成（全面書き直しと同じ扱い）。

判断結果（全面書き直し／部分修正／新規作成のいずれか）とその理由を記録する。

## Step 6: 反映と報告

Step 5 の判断に従い、`$TARGET_DIR/CLAUDE.md` を `Write`（全面書き直し・新規作成の場合）または `Edit`（部分修正の場合）で書き換える。

書き込みが失敗した場合（権限不足等）はエラーを報告して中断する。

実行後、以下をユーザーに報告する:

- 全面書き直し／部分修正／新規作成のいずれを行ったか、その判断理由。
- 主な変更点のサマリー。
- 対象ディレクトリが git 管理下であれば、既存ファイルの変更は `git diff`、新規作成は `git status` で詳細を確認できる旨。
- Step 3 のライブ検索が失敗していた場合はその旨。
- 対象ディレクトリが git 管理下でなかった場合はその旨（Step 1 で記録した警告）。
