# book000/dotfiles

```bash
sh -c "$(curl -fsSL get.chezmoi.io)" -- init --apply book000
cp ~/.gitconfig.local.example ~/.gitconfig.local
vim ~/.gitconfig.local
cp ~/.env.example ~/.env
vim ~/.env
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
