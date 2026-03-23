# AI CLI ツールのエイリアス設定
# --dangerously-skip-permissions や --yolo は、確認プロンプトをスキップして実行するためのオプションです。
# AI エージェントの自動更新 (update-ai-agents.sh --quick --only <agent>) を各 CLI 実行前に実行します。
alias claude='[ -x ~/bin/update-ai-agents.sh ] && ~/bin/update-ai-agents.sh --quick --only claude; ~/.local/share/chezmoi/update.sh; claude --dangerously-skip-permissions'
alias codex='[ -x ~/bin/update-ai-agents.sh ] && ~/bin/update-ai-agents.sh --quick --only codex; ~/.local/share/chezmoi/update.sh; codex --yolo'
alias gemini='[ -x ~/bin/update-ai-agents.sh ] && ~/bin/update-ai-agents.sh --quick --only gemini; ~/.local/share/chezmoi/update.sh; gemini --yolo'
# copilot コマンドのラッパー関数。
# AI エージェント・chezmoi の更新を行い、カレントディレクトリに .copilot/mcp-config.json が
# 存在する場合は --additional-mcp-config オプションを付与して実行する。
# 既存セッションで旧エイリアスが残存している場合に備えて、関数定義前に unalias する。
unalias copilot 2>/dev/null
copilot() {
  # copilot のみアップデートチェック・chezmoi の更新を実行
  [ -x ~/bin/update-ai-agents.sh ] && ~/bin/update-ai-agents.sh --quick --only copilot
  ~/.local/share/chezmoi/update.sh
  # カレントディレクトリに .copilot/mcp-config.json が存在する場合は追加引数を設定
  if [ -f ".copilot/mcp-config.json" ]; then
    command copilot --yolo --additional-mcp-config "@.copilot/mcp-config.json" "$@"
  else
    command copilot --yolo "$@"
  fi
}
alias happy='~/.local/share/chezmoi/update.sh; happy --dangerously-skip-permissions'
