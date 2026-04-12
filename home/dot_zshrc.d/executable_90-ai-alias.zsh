# AI CLI ツールのエイリアス設定
# --dangerously-skip-permissions や --yolo は、確認プロンプトをスキップして実行するためのオプションです。
# AI エージェントの自動更新 (update-ai-agents.sh --quick) を各 CLI 実行前に実行します。
# claude コマンドのラッパー関数。
# AI エージェントの更新を行い、--dangerously-skip-permissions を付与して実行する。
# ただし remote-control サブコマンドはフラグを付与しない。
# （--dangerously-skip-permissions が前置されると process.argv[2] が "remote-control" でなくなり、
#   コマンドディスパッチが失敗して "Unknown argument: remote-control" エラーが発生するため）
# 既存セッションで旧エイリアスが残存している場合に備えて、関数定義前に unalias する。
unalias claude 2>/dev/null
claude() {
  [ -x ~/bin/update-ai-agents.sh ] && ~/bin/update-ai-agents.sh --quick
  case "$1" in
    remote-control|rc)
      command claude "$@" ;;
    *)
      command claude --dangerously-skip-permissions "$@" ;;
  esac
}
alias codex='[ -x ~/bin/update-ai-agents.sh ] && ~/bin/update-ai-agents.sh --quick; codex --yolo'
alias gemini='[ -x ~/bin/update-ai-agents.sh ] && ~/bin/update-ai-agents.sh --quick; gemini --yolo'
# copilot コマンドのラッパー関数。
# AI エージェントの更新を行い、カレントディレクトリに .copilot/mcp-config.json が
# 存在する場合は --additional-mcp-config オプションを付与して実行する。
# 既存セッションで旧エイリアスが残存している場合に備えて、関数定義前に unalias する。
unalias copilot 2>/dev/null
copilot() {
  # AI エージェントの更新を実行
  [ -x ~/bin/update-ai-agents.sh ] && ~/bin/update-ai-agents.sh --quick
  # カレントディレクトリに .copilot/mcp-config.json が存在する場合は追加引数を設定
  if [ -f ".copilot/mcp-config.json" ]; then
    command copilot --yolo --additional-mcp-config "@.copilot/mcp-config.json" "$@"
  else
    command copilot --yolo "$@"
  fi
}
# rtk コマンドのラッパー関数。
# AI エージェントの更新を行い、rtk コマンドを実行する。
# 既存セッションで旧エイリアスが残存している場合に備えて、関数定義前に unalias する。
unalias rtk 2>/dev/null
rtk() {
  [ -x ~/bin/update-ai-agents.sh ] && ~/bin/update-ai-agents.sh --quick
  command rtk "$@"
}
