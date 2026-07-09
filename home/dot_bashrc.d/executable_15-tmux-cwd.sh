# tmux セッション選択UI（10-tmux-selector）の cwd 表示を最新に保つため、
# プロンプト表示のたびに TMUX_PROJECT_DIR をカレントディレクトリで更新する。
# tmux 外では何もしない。
# $PWD が前回実行時から変化していない場合は tmux コマンドの起動自体を
# スキップし、プロンプト表示のたびに外部コマンドが走ることによる遅延を避ける。
__bashrc_update_tmux_project_dir() {
  [[ -n "${TMUX:-}" ]] || return 0
  [[ "$PWD" == "${__BASHRC_TMUX_PROJECT_DIR_LAST:-}" ]] && return 0
  tmux set-environment TMUX_PROJECT_DIR "$PWD" 2>/dev/null
  __BASHRC_TMUX_PROJECT_DIR_LAST="$PWD"
}

# PROMPT_COMMAND への登録は idempotent に行う。
# Bash 5.1+ では PROMPT_COMMAND が配列になり得るため、スカラーへの単純代入で
# 他要素を破壊しないよう配列/スカラーそれぞれの形で分岐する。
if declare -p PROMPT_COMMAND 2>/dev/null | grep -q '^declare -a'; then
  if [[ ! " ${PROMPT_COMMAND[*]} " == *" __bashrc_update_tmux_project_dir "* ]]; then
    PROMPT_COMMAND+=(__bashrc_update_tmux_project_dir)
  fi
elif [[ "${PROMPT_COMMAND:-}" != *"__bashrc_update_tmux_project_dir"* ]]; then
  # shellcheck disable=SC2178,SC2128 # このブランチは PROMPT_COMMAND が配列でない場合のみ通る（上の if 条件で排他）
  PROMPT_COMMAND="${PROMPT_COMMAND:+${PROMPT_COMMAND}; }__bashrc_update_tmux_project_dir"
fi
