# AI CLI ツールのエイリアス設定
# --yolo は、確認プロンプトをスキップして実行するためのオプションです。
# claude は --permission-mode auto で、分類器による安全チェックを介して確認プロンプトを削減します。
# AI エージェントの自動更新 (update-ai-agents.sh --quick --only <agent>) を各 CLI 実行前に実行します。
# claude コマンドのラッパー関数。
# AI エージェント・chezmoi の更新を行い、--permission-mode auto を付与して実行する。
# ただし remote-control サブコマンドはフラグを付与しない。
# （auto モードのフラグが前置されると process.argv[2] が "remote-control" でなくなり、
#   コマンドディスパッチが失敗して "Unknown argument: remote-control" エラーが発生するため）
# 既存セッションで旧エイリアスが残存している場合に備えて、関数定義前に unalias する。
unalias claude 2>/dev/null
# カレントディレクトリを Claude Code のワークスペース信頼済みディレクトリとして
# ~/.claude.json に登録する。
# Workspace Trust dialog の非永続化は --dangerously-skip-permissions 固有ではなく
# Claude Code 全体の既知の問題（Issue #165 で検証済み）であり、hasTrustDialogAccepted が
# 永続化されないと statusLine や hooks が無音でスキップされてしまう。auto モードでも同様に必要な対策。
_claude_trust_cwd() {
  local config="$HOME/.claude.json"
  [ -f "$config" ] || return 0
  command -v jq > /dev/null 2>&1 || return 0
  if [ "$(jq -r --arg p "$PWD" '.projects[$p].hasTrustDialogAccepted // false' "$config" 2> /dev/null)" != "true" ]; then
    local tmp perm
    tmp=$(mktemp "${config}.XXXXXX") || return 0
    # 元ファイルのパーミッションを一時ファイルに反映する (GNU stat / BSD stat の両方に対応)
    perm=$(stat -c '%a' "$config" 2> /dev/null || stat -f '%Lp' "$config" 2> /dev/null)
    [ -n "$perm" ] && chmod "$perm" "$tmp"
    if jq --arg p "$PWD" '.projects[$p] = ((.projects[$p] // {}) + {hasTrustDialogAccepted: true})' "$config" > "$tmp"; then
      mv "$tmp" "$config"
    else
      rm -f "$tmp"
    fi
  fi
}
claude() {
  [ -x ~/bin/update-ai-agents.sh ] && ~/bin/update-ai-agents.sh --quick --only claude
  ~/.local/share/chezmoi/update.sh
  case "$1" in
    remote-control|rc)
      command claude "$@" ;;
    *)
      _claude_trust_cwd
      command claude --permission-mode auto "$@" ;;
  esac
}
alias codex='[ -x ~/bin/update-ai-agents.sh ] && ~/bin/update-ai-agents.sh --quick --only codex; ~/.local/share/chezmoi/update.sh; codex --yolo'
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
