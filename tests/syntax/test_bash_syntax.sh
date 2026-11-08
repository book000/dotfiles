#!/bin/bash
# bash -n による構文チェック

set -euo pipefail

echo "Checking bash syntax..."

FAILED=0

# シェル断片を含む全スクリプトを構文チェック
# worktree 配下は本体の複製で二重に検査されるため除外する
while IFS= read -r -d '' script; do
  # シェバンの有無にかかわらず bash として構文チェックする
  if ! bash -n "$script"; then
    echo "❌ Syntax error: $script"
    FAILED=1
  else
    echo "✅ Syntax OK: $script"
  fi
done < <(find . -type f \( -name "*.sh" -o -name "executable_*" \) \
  -not -path "./.bare/*" \
  -not -path "./bin/*" \
  -not -path "./.claude/worktrees/*" \
  -not -path "./.worktrees/*" \
  -print0)

# 主要な設定ファイルも bash として構文チェック
for config in home/dot_bash_env home/dot_bashrc home/dot_bash_profile; do
  if [ -f "$config" ]; then
    if ! bash -n "$config"; then
      echo "❌ Syntax error: $config"
      FAILED=1
    else
      echo "✅ Syntax OK: $config"
    fi
  fi
done

# POSIX profile は sh として構文チェック
if [ -f home/dot_profile ]; then
  if ! sh -n home/dot_profile; then
    echo "❌ Syntax error: home/dot_profile"
    FAILED=1
  else
    echo "✅ Syntax OK (as sh): home/dot_profile"
  fi
fi

exit $FAILED
