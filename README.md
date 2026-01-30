# book000/dotfiles

```bash
sh -c "$(curl -fsSL get.chezmoi.io)" -- init --apply book000
cp ~/.gitconfig.local.example ~/.gitconfig.local
vim ~/.gitconfig.local
cp ~/.env.example ~/.env
vim ~/.env
```

## 便利なコマンド

### issue-pr

GitHub の issue を確認し、対応のためのブランチを作成して、Claude CLI で PR を作成します。

```bash
issue-pr <issue_number>
```

- issue のタイトルから適切なブランチ名を自動生成します
- デフォルトブランチ（master または main）から最新の状態でブランチを作成します
- Claude CLI を起動して issue の対応を依頼します
