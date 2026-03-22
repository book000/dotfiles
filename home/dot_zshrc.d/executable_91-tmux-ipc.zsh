# tmux IPC ヘルパーエイリアス
# AI エージェント間のメッセージ通信 (tmux-ipc) を操作するためのエイリアス定義。

# tmux 環境かどうかを確認してから定義する
if [[ -n "${TMUX:-}" && -x "$HOME/bin/tmux-ipc-register.sh" ]]; then

  # 現在のセッションを IPC に登録する
  alias ipc-register='~/bin/tmux-ipc-register.sh'

  # 指定セッションにメッセージを送信する
  # Usage: ipc-send <to_session_id> <body> [ttl_seconds]
  alias ipc-send='~/bin/tmux-ipc-send.sh'

  # inbox のメッセージを受信して処理する
  alias ipc-receive='~/bin/tmux-ipc-receive.sh'

  # 期限切れメッセージとセッションをクリーンアップする
  alias ipc-cleanup='~/bin/tmux-ipc-cleanup.sh'

  # 登録済みセッション一覧を表示する
  ipc-list() {
    local registry="/tmp/tmux-ipc/registry.json"
    if [[ ! -f "$registry" ]]; then
      echo "[tmux-ipc] No sessions registered"
      return 0
    fi
    echo "[tmux-ipc] Registered sessions:"
    jq -r '.sessions[] | "  \(.id)  agent=\(.agent)  updated=\(.updated | todate)"' \
      "$registry" 2>/dev/null || cat "$registry"
  }

fi
