# tmux セッション選択UI（10-tmux-selector）の cwd 表示を最新に保つため、
# プロンプト表示のたびに TMUX_PROJECT_DIR をカレントディレクトリで更新する。
# tmux 外では何もしない。
# $PWD が前回実行時から変化していない場合は tmux コマンドの起動自体を
# スキップし、プロンプト表示のたびに外部コマンドが走ることによる遅延を避ける。
_update_tmux_project_dir() {
  [[ -n "${TMUX:-}" ]] || return 0
  [[ "$PWD" == "${_TMUX_PROJECT_DIR_LAST:-}" ]] && return 0
  tmux set-environment TMUX_PROJECT_DIR "$PWD" 2>/dev/null
  _TMUX_PROJECT_DIR_LAST="$PWD"
}

# add-zsh-hook を用いて precmd フックに idempotent に登録する
autoload -Uz add-zsh-hook
add-zsh-hook precmd _update_tmux_project_dir
