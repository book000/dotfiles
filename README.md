# book000/dotfiles

```bash
sh -c "$(curl -fsSL get.chezmoi.io)" -- init --apply book000
cp ~/.gitconfig.local.example ~/.gitconfig.local
vim ~/.gitconfig.local
cp ~/.env.example ~/.env
vim ~/.env
```

## Claude Code プラグイン

### issue-pr

GitHub の issue を確認し、対応のためのブランチを作成して PR を作成する Claude Code プラグインです。

```
/issue-pr <issue_number>
```

- issue のタイトルから適切なブランチ名を自動生成します
- デフォルトブランチ（master または main）から最新の状態でブランチを作成します
- issue の内容に基づいて対応を行い、PR を作成します
