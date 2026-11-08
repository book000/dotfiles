#!/bin/bash
# rtk-rewrite.sh と、rtk が実行前に照合する hash ファイル (.rtk-hook.sha256) の整合性テスト。
# rtk は hooks/.rtk-hook.sha256 と実際の hooks/rtk-rewrite.sh の sha256 が食い違うと
# "RTK will not execute" で全コマンドを拒否するため、フックを編集したら hash も同じ変更で更新する必要がある。

set -uo pipefail

echo "Testing rtk-rewrite.sh hash sidecar consistency..."

FAILED=0
HOOK="home/dot_claude/hooks/executable_rtk-rewrite.sh"
HASH_FILE="home/dot_claude/hooks/readonly_dot_rtk-hook.sha256"

ok() { echo "✅ $1"; }
ng() { echo "❌ $1"; FAILED=1; }

if [[ ! -f "$HOOK" ]]; then
  ng "hook not found: $HOOK"
  exit 1
fi
if [[ ! -f "$HASH_FILE" ]]; then
  ng "hash file not found: $HASH_FILE"
  exit 1
fi

ACTUAL=$(sha256sum "$HOOK" | cut -d' ' -f1)
# rtk が書く形式は sha256sum 互換 (`<64hex>  rtk-rewrite.sh`) で、ファイル名は配備後の名前 (executable_ なし)。
EXPECTED_CONTENT="${ACTUAL}  rtk-rewrite.sh"
CONTENT=$(cat "$HASH_FILE")

if [[ "$CONTENT" == "$EXPECTED_CONTENT" ]]; then
  ok "hash file matches the hook content"
else
  ng "hash file is stale. Run: printf '%s  rtk-rewrite.sh\\n' \"\$(sha256sum $HOOK | cut -d' ' -f1)\" > $HASH_FILE"
  echo "   expected: $EXPECTED_CONTENT"
  echo "   actual:   $CONTENT"
fi

# 末尾改行ありの 1 行であること (sha256sum -c 互換の形式を保つ)
if [[ "$(wc -l < "$HASH_FILE")" -eq 1 && "$(tail -c1 "$HASH_FILE" | od -An -c | tr -d ' ')" == '\n' ]]; then
  ok "hash file is a single newline-terminated line"
else
  ng "hash file must be exactly one newline-terminated line"
fi

# rtk が参照する実名で sha256sum -c が通ること (配備後の hooks/ を再現)
TMPDIR_CHECK=$(mktemp -d)
trap 'rm -rf "$TMPDIR_CHECK"' EXIT
cp "$HOOK" "$TMPDIR_CHECK/rtk-rewrite.sh"
cp "$HASH_FILE" "$TMPDIR_CHECK/.rtk-hook.sha256"
if (cd "$TMPDIR_CHECK" && sha256sum -c .rtk-hook.sha256 >/dev/null 2>&1); then
  ok "sha256sum -c passes for the deployed layout"
else
  ng "sha256sum -c fails for the deployed layout"
fi

if [[ "$FAILED" -ne 0 ]]; then
  echo "rtk hook hash tests FAILED"
  exit 1
fi
echo "rtk hook hash tests passed"
