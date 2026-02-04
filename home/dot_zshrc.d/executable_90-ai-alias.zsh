# AI CLI ツールのエイリアス設定
# --dangerously-skip-permissions や --yolo は、確認プロンプトをスキップして実行するためのオプションです。
# AI エージェントの自動更新 (update-ai-agents.sh --quick) を各 CLI 実行前に実行します。
alias claude='~/bin/update-ai-agents.sh --quick; claude --dangerously-skip-permissions'
alias codex='~/bin/update-ai-agents.sh --quick; codex --yolo'
alias gemini='~/bin/update-ai-agents.sh --quick; gemini --yolo'
alias copilot='~/bin/update-ai-agents.sh --quick; copilot --yolo'
