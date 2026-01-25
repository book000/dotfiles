# SSH接続かつtmux外かつTTYありのときのみ自動起動（scp/rsync等を避ける）
if [[ -z "${TMUX:-}" && -n "${SSH_CONNECTION:-}" && -t 0 && -t 1 ]]; then
  if command -v bash >/dev/null 2>&1; then
    while true; do
      sleep 1
      TMUX_SELECTOR_DISABLE_AUTO=1 bash -lc 'tmux_session_selector' || break
    done
  fi
fi
