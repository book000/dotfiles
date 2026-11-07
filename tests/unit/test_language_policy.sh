#!/bin/bash
# 言語規約のドキュメント整合を検証する。

set -euo pipefail

echo "Testing language policy consistency..."

FAILED=0
cd "$(dirname "$0")/../.."

ok() { echo "✅ $1"; }
ng() { echo "❌ $1"; FAILED=1; }

# grep の終了コード 2 以上(エラー)は「該当なし」とみなさず失敗させる
match() {
  local rc=0
  "$@" || rc=$?
  if [[ $rc -ge 2 ]]; then
    echo "grep failed (exit $rc): $*" >&2
    exit 2
  fi
  return "$rc"
}

# 取り込み先が無ければ @AGENTS.md は何も読み込まない
if [[ -f AGENTS.md ]]; then
  ok "AGENTS.md exists"
else
  ng "AGENTS.md is missing"
fi

# コードフェンス内ではなく単独行としての取り込みを要求する
if match awk '/^```/ { f = !f; next } !f && /^@AGENTS\.md$/ { found = 1 } END { exit !found }' CLAUDE.md; then
  ok "CLAUDE.md imports @AGENTS.md"
else
  ng "CLAUDE.md does not import @AGENTS.md"
fi

# 英語限定のファイルに日本語が混入していない
if match env LC_ALL=C.UTF-8 grep -rP "[\x{3040}-\x{30FF}\x{4E00}-\x{9FFF}]" home/dot_codex home/dot_agents .github/copilot-instructions.md AGENTS.md CLAUDE.md --include=*.md; then
  ng "Japanese text found in Markdown under home/dot_codex or home/dot_agents, or in .github/copilot-instructions.md, AGENTS.md, CLAUDE.md"
else
  ok "No Japanese text in Markdown under home/dot_codex or home/dot_agents, or in .github/copilot-instructions.md, AGENTS.md, CLAUDE.md"
fi

# home/dot_claude の Markdown は英語限定。日本語を意図して含むファイルだけを許可リストに載せる(識別子・UI ラベル・成果物テンプレート・IME 例)
JA_ALLOWED=(
  home/dot_claude/rules/coding-csharp.md
  home/dot_claude/skills/glitchtip-pr-deep/SKILL.md
  home/dot_claude/skills/issue-pr-deep/SKILL.md
  home/dot_claude/skills/pr-health-monitor/SKILL.md
  home/dot_claude/skills/proxmox/SKILL.md
  home/dot_claude/skills/ticket-pr/SKILL.md
  home/dot_claude/skills/trilium/SKILL.md
)
CLAUDE_JA_FILES=()
while IFS= read -r f; do
  [[ " ${JA_ALLOWED[*]} " == *" $f "* ]] && continue
  if match env LC_ALL=C.UTF-8 grep -qP "[\x{3040}-\x{30FF}\x{4E00}-\x{9FFF}]" "$f"; then
    CLAUDE_JA_FILES+=("$f")
  fi
done < <(find home/dot_claude -name '*.md' | sort)
if [[ ${#CLAUDE_JA_FILES[@]} -gt 0 ]]; then
  ng "Japanese text found in Markdown under home/dot_claude outside JA_ALLOWED: ${CLAUDE_JA_FILES[*]}"
else
  ok "No Japanese text in Markdown under home/dot_claude outside JA_ALLOWED"
fi

if [[ $FAILED -eq 0 ]]; then
  echo "✅ All language policy tests passed"
  exit 0
else
  echo "❌ Some language policy tests failed"
  exit 1
fi
