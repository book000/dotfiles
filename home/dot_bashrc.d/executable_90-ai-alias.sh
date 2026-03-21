# AI CLI ツールのエイリアス設定
# --dangerously-skip-permissions や --yolo は、確認プロンプトをスキップして実行するためのオプションです。
# AI エージェントの自動更新 (update-ai-agents.sh --quick) を各 CLI 実行前に実行します。
alias claude='[ -x ~/bin/update-ai-agents.sh ] && ~/bin/update-ai-agents.sh --quick; ~/.local/share/chezmoi/update.sh; claude --dangerously-skip-permissions'
alias codex='[ -x ~/bin/update-ai-agents.sh ] && ~/bin/update-ai-agents.sh --quick; ~/.local/share/chezmoi/update.sh; codex --yolo'
alias gemini='[ -x ~/bin/update-ai-agents.sh ] && ~/bin/update-ai-agents.sh --quick; ~/.local/share/chezmoi/update.sh; gemini --yolo'
copilot() {
  # AI エージェントの更新と chezmoi の更新を実行
  [ -x ~/bin/update-ai-agents.sh ] && ~/bin/update-ai-agents.sh --quick
  ~/.local/share/chezmoi/update.sh
  # カレントディレクトリに .copilot/mcp-config.json が存在する場合は追加引数を設定
  if [ -f ".copilot/mcp-config.json" ]; then
    command copilot --yolo --additional-mcp-config "@.copilot/mcp-config.json" "$@"
  else
    command copilot --yolo "$@"
  fi
}
alias happy='[ -x ~/bin/update-ai-agents.sh ] && ~/bin/update-ai-agents.sh --quick; ~/.local/share/chezmoi/update.sh; happy --dangerously-skip-permissions'
