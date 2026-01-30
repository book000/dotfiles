# AI CLI ツールのエイリアス設定
# --dangerously-skip-permissions や --yolo は、確認プロンプトをスキップして実行するためのオプションです。
alias claude='~/.local/share/chezmoi/update.sh; claude --dangerously-skip-permissions'
alias codex='~/.local/share/chezmoi/update.sh; codex --yolo'
alias gemini='~/.local/share/chezmoi/update.sh; gemini --yolo'
alias copilot='~/.local/share/chezmoi/update.sh; copilot --yolo'
