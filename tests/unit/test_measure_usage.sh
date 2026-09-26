#!/bin/bash
# deep-review measure-usage.sh のユニットテスト (smoke test)。固定 fixture JSONL に対する出力を検証する。

set -uo pipefail

echo "Testing deep-review measure-usage.sh..."

FAILED=0
SCRIPT="$PWD/home/dot_agents/skills/deep-review/scripts/executable_measure-usage.sh"
FIXTURE_DIR=$(mktemp -d)
trap 'rm -rf "$FIXTURE_DIR"' EXIT

ok() { echo "✅ $1"; }
ng() { echo "❌ $1"; FAILED=1; }

expect_eq() {
  if [[ "$2" == "$3" ]]; then ok "$1"; else ng "$1 (got '$2', want '$3')"; fi
}
expect_ok() {
  local msg="$1"; shift
  if "$@" >/dev/null 2>&1; then ok "$msg"; else ng "$msg (expected success)"; fi
}

# --- fixture 1: stage A. 2 モデル・SendMessage 2 件・merge-blocker 1 件 ---
cat >"$FIXTURE_DIR/a.jsonl" <<'EOF'
{"type":"assistant","timestamp":"2026-09-27T10:00:00.000Z","message":{"model":"claude-sonnet-5","usage":{"input_tokens":100,"cache_creation_input_tokens":10,"cache_read_input_tokens":5,"output_tokens":20},"content":[{"type":"text","text":"hi"}]}}
{"type":"assistant","timestamp":"2026-09-27T10:00:30.000Z","message":{"model":"claude-sonnet-5","usage":{"input_tokens":50,"cache_creation_input_tokens":0,"cache_read_input_tokens":100,"output_tokens":30},"content":[{"type":"tool_use","name":"SendMessage","input":{"to":"reviewer-a"}}]}}
{"type":"assistant","timestamp":"2026-09-27T10:01:00.000Z","message":{"model":"claude-opus-4","usage":{"input_tokens":200,"output_tokens":40},"content":[{"type":"tool_use","name":"Bash","input":{"command":"echo \"class\":\"merge-blocker\""}}]}}
{"type":"user","timestamp":"2026-09-27T10:01:10.000Z","message":{"content":"noise, not counted"}}
{"type":"assistant","timestamp":"2026-09-27T10:02:00.000Z","message":{"model":"claude-opus-4","content":[{"type":"tool_use","name":"SendMessage","input":{"to":"reviewer-a"}}]}}
EOF

# --- fixture 2: stage B. follow-up/unverified/out-of-scope 各1件、SendMessage 0件 ---
cat >"$FIXTURE_DIR/b.jsonl" <<'EOF'
{"type":"assistant","timestamp":"2026-09-27T11:00:00.000Z","message":{"model":"claude-haiku-4","usage":{"input_tokens":5,"output_tokens":1},"content":[{"type":"tool_use","name":"Bash","input":{"command":"echo \"class\":\"follow-up\""}}]}}
{"type":"assistant","timestamp":"2026-09-27T11:00:05.000Z","message":{"model":"claude-haiku-4","usage":{"input_tokens":5,"output_tokens":1},"content":[{"type":"tool_use","name":"Bash","input":{"command":"echo \"class\":\"unverified\""}}]}}
{"type":"assistant","timestamp":"2026-09-27T11:00:10.000Z","message":{"model":"claude-haiku-4","usage":{"input_tokens":5,"output_tokens":1},"content":[{"type":"tool_use","name":"Bash","input":{"command":"echo \"class\":\"out-of-scope\""}}]}}
EOF

OUT_JSON=$("$SCRIPT" --stage a:"$FIXTURE_DIR/a.jsonl" --stage b:"$FIXTURE_DIR/b.jsonl" --stage missing:/no/such/file.jsonl --format json 2>/dev/null)

# 1. 段階別トークン集計
expect_eq "stage a input_tokens" "$(jq -r '.stages[0].input_tokens' <<<"$OUT_JSON")" 350
expect_eq "stage a cache_creation_input_tokens" "$(jq -r '.stages[0].cache_creation_input_tokens' <<<"$OUT_JSON")" 10
expect_eq "stage a cache_read_input_tokens" "$(jq -r '.stages[0].cache_read_input_tokens' <<<"$OUT_JSON")" 105
expect_eq "stage a output_tokens" "$(jq -r '.stages[0].output_tokens' <<<"$OUT_JSON")" 90
expect_eq "missing stage tokens are N/A (null)" "$(jq -r '.stages[2].input_tokens' <<<"$OUT_JSON")" null

# 2. モデル別内訳
expect_eq "stage a model breakdown: claude-sonnet-5 count" \
  "$(jq -r '.stages[0].models[] | select(.model=="claude-sonnet-5") | .count' <<<"$OUT_JSON")" 2
expect_eq "stage a model breakdown: claude-opus-4 count" \
  "$(jq -r '.stages[0].models[] | select(.model=="claude-opus-4") | .count' <<<"$OUT_JSON")" 2

# 3. 起動件数 (assistant メッセージ数)
expect_eq "stage a invocation_count" "$(jq -r '.stages[0].invocation_count' <<<"$OUT_JSON")" 4
expect_eq "missing stage invocation_count" "$(jq -r '.stages[2].invocation_count' <<<"$OUT_JSON")" 0

# 4. reviewer 別 idle→nudge→再dispatch 検出 (SendMessage 出現回数)
expect_eq "stage a SendMessage to reviewer-a count" \
  "$(jq -r '.stages[0].sendmessage_targets[] | select(.to=="reviewer-a") | .count' <<<"$OUT_JSON")" 2
expect_eq "stage b has no SendMessage targets" "$(jq -r '.stages[1].sendmessage_targets | length' <<<"$OUT_JSON")" 0

# 5. 所要時間 (タイムスタンプ差分、秒)
expect_eq "stage a duration_seconds" "$(jq -r '.stages[0].duration_seconds' <<<"$OUT_JSON")" 120

# 6. 指摘候補数/verified/unverified/out-of-scope 内訳
expect_eq "stage a merge-blocker count" "$(jq -r '.stages[0].findings.merge_blocker' <<<"$OUT_JSON")" 1
expect_eq "stage b follow-up count" "$(jq -r '.stages[1].findings.follow_up' <<<"$OUT_JSON")" 1
expect_eq "stage b unverified count" "$(jq -r '.stages[1].findings.unverified' <<<"$OUT_JSON")" 1
expect_eq "stage b out-of-scope count" "$(jq -r '.stages[1].findings.out_of_scope' <<<"$OUT_JSON")" 1

# 7. フッターの注記文字列
expect_eq "note mentions it is not billing/plan-quota usage" \
  "$(jq -r '.note | contains("not API billing")' <<<"$OUT_JSON")" true

# 8. 存在しないファイルを渡してもクラッシュしない (N/A を返す)
expect_ok "nonexistent file path does not crash" "$SCRIPT" --stage x:/no/such/file.jsonl --format json

# 9. Markdown + JSON 併記のデフォルト出力に表と ```json ブロックが含まれる
MD_OUT=$("$SCRIPT" --stage a:"$FIXTURE_DIR/a.jsonl" 2>/dev/null)
expect_ok "default (both) output contains a markdown table header" grep -q '| stage |' <<<"$MD_OUT"
expect_ok "default (both) output contains a json fence" grep -q '```json' <<<"$MD_OUT"

# --- fixture 3: class 内訳がエスケープなしの生 JSON (例: ledger スナップショット) でも検出される ---
cat >"$FIXTURE_DIR/c.jsonl" <<'EOF'
{"note":"ledger snapshot","class":"merge-blocker","status":"open"}
EOF
OUT_JSON_C=$("$SCRIPT" --stage c:"$FIXTURE_DIR/c.jsonl" --format json 2>/dev/null)
expect_eq "unescaped class form is counted (merge-blocker)" \
  "$(jq -r '.stages[0].findings.merge_blocker' <<<"$OUT_JSON_C")" 1

if [ $FAILED -eq 0 ]; then
  echo "✅ All deep-review measure-usage tests passed"
else
  echo "❌ Some deep-review measure-usage tests failed"
  exit 1
fi
