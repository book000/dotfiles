## Codex Skills

Codex CLI では、Claude Code のような任意の custom slash command を追加せず、skill を使ってコマンド相当のワークフローを提供する。
Codex は repo / user / admin / system scope の skill を読み込めるが、この dotfiles では user scope の `~/.agents/skills` を管理する。

- この dotfiles が管理する skill は `~/.agents/skills` に配置する
- 明示的に呼び出す場合は `$` で skill を指定する
- この dotfiles では以下の skill を提供する
  - `$issue-pr`
  - `$ticket-pr`
  - `$pr-health-monitor`
  - `$handle-pr-reviews`
- skill を更新したのに一覧へ反映されない場合は Codex を再起動する

## 作業方針

- 基本的な振る舞い・Git 運用・コーディングルール等の共通方針は `~/.claude/CLAUDE.md` を参照すること
