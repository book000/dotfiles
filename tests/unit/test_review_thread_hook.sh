#!/bin/bash
# require-review-thread-fixes.sh (Stop フック) の挙動テスト。gh はスタブに差し替える。

set -euo pipefail

# BASH_ENV (~/.bash_env) が mise の PATH を先頭に追加し、PATH 先頭に置いたスタブの gh が本物に隠れるため無効化する
unset BASH_ENV

echo "Testing require-review-thread-fixes hook..."

FAILED=0
HOOK="$PWD/home/dot_claude/hooks/executable_require-review-thread-fixes.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
GH_LOG="$TMP/gh.log"
export GH_LOG

mkdir -p "$TMP/bin" "$TMP/home/.claude/data" "$TMP/repo"
# gh スタブ: 引数を記録し、未解決スレッド 1 件の GraphQL 応答を返す
cat >"$TMP/bin/gh" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"$GH_LOG"
cat <<'JSON'
{"data":{"repository":{"pullRequest":{"reviewThreads":{"nodes":[{"id":"T1","isResolved":false,"path":"a.sh","line":1,"comments":{"nodes":[{"author":{"login":"rev"},"body":"fix"}]}}]}}}}}
JSON
EOF
chmod +x "$TMP/bin/gh"

# origin = フォーク、upstream = 本家のチェックアウトで実行する
git -C "$TMP/repo" init -q
git -C "$TMP/repo" remote add origin git@github.com:akubiusa/dotfiles.git
git -C "$TMP/repo" remote add upstream git@github.com:book000/dotfiles.git

run_hook() {
  : >"$GH_LOG"
  (cd "$TMP/repo" && HOME="$TMP/home" PATH="$TMP/bin:$PATH" bash "$HOOK" <<<"$1")
}
# 引数: 説明、期待 (block / pass)、gh に渡るはずの文字列 (空なら gh 未呼び出しを期待)。入力はグローバルの INPUT を使う
check() {
  local msg="$1" expect="$2" want="$3" out
  out=$(run_hook "$INPUT") || true
  if [[ "$expect" == "block" ]] && ! jq -e '.decision == "block"' <<<"$out" >/dev/null 2>&1; then
    echo "❌ $msg (expected block, got: $out)"; FAILED=1; return
  fi
  if [[ "$expect" == "pass" ]] && [[ -n "$out" ]]; then
    echo "❌ $msg (expected no output, got: $out)"; FAILED=1; return
  fi
  if [[ -n "$want" ]] && ! grep -qF -- "$want" "$GH_LOG"; then
    echo "❌ $msg (gh args missing '$want'; log: $(cat "$GH_LOG"))"; FAILED=1; return
  fi
  if [[ -z "$want" ]] && [[ -s "$GH_LOG" ]]; then
    echo "❌ $msg (gh must not be called; log: $(cat "$GH_LOG"))"; FAILED=1; return
  fi
  echo "✅ $msg"
}
write_state() {
  jq -nc --arg u "$1" --argjson t "$(date +%s)" '{session_id: "s1", timestamp: $t, pr_url: $u}' \
    >"$TMP/home/.claude/data/session-state.json"
}

# 1. フォーク構成: PR URL の本家リポジトリを GraphQL に渡す (origin ではない)
write_state "https://github.com/book000/dotfiles/pull/445"
INPUT='{"session_id":"s1"}'
check "fork: queries the PR URL repository, not origin" block "owner=book000 -f repo=dotfiles -F number=445"

# 2. ドットを含むリポジトリ名を切り詰めない
write_state "https://github.com/octo/my.repo.name/pull/7"
check "dotted repo name is passed intact" block "owner=octo -f repo=my.repo.name -F number=7"

# 3. transcript フォールバック: text ブロックと文字列 content の両方から URL を拾う
rm -f "$TMP/home/.claude/data/session-state.json"
jq -nc '{type:"assistant",message:{content:[{type:"text",text:"PR https://github.com/book000/dotfiles/pull/12 を作成"}]}}' >"$TMP/t.jsonl"
INPUT=$(jq -nc --arg p "$TMP/t.jsonl" '{session_id:"s1",transcript_path:$p}')
check "transcript fallback: URL in a text content block" block "owner=book000 -f repo=dotfiles -F number=12"
jq -nc '{type:"assistant",message:{content:["see https://github.com/o/r/pull/3"]}}' >"$TMP/t.jsonl"
check "transcript fallback: URL in a string content item" block "owner=o -f repo=r -F number=3"

# 4. PR が見つからない場合はブロックせず gh も呼ばない
jq -nc '{type:"assistant",message:{content:[{type:"text",text:"no pr here"}]}}' >"$TMP/t.jsonl"
check "no PR URL: no block and no gh call" pass ""

if [ $FAILED -eq 0 ]; then
  echo "✅ All review-thread hook tests passed"
else
  echo "❌ Some review-thread hook tests failed"
  exit 1
fi
