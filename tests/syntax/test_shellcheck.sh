#!/bin/bash
# シェルスクリプトの静的解析 (shellcheck)

set -euo pipefail

echo "Running shellcheck on all shell scripts..."

FAILED=0

# シェル断片 (shebang なし) を含む全スクリプトを検査
# -print0 と while read でパス名の空白を安全に処理
while IFS= read -r -d '' script; do
  # シェバンの有無にかかわらず bash として検査する
  if head -n 1 "$script" | grep -qE '^#!(.*/)?(bash|sh)'; then
    # bash / sh の shebang がある場合
    if ! shellcheck "$script"; then
      echo "❌ Shellcheck failed: $script"
      FAILED=1
    else
      echo "✅ Shellcheck passed: $script"
    fi
  else
    # シェバンがない場合は bash として明示的に解析
    if ! shellcheck -s bash "$script"; then
      echo "❌ Shellcheck failed (as bash): $script"
      FAILED=1
    else
      echo "✅ Shellcheck passed (as bash): $script"
    fi
  fi
done < <(find . -type f \( -name "*.sh" -o -name "executable_*" \) \
  -not -path "./.bare/*" \
  -not -path "./bin/*" \
  -print0)

# 主要な設定ファイルも bash として検査
for config in home/dot_bashrc home/dot_bash_profile; do
  if [ -f "$config" ]; then
    if ! shellcheck -s bash "$config"; then
      echo "❌ Shellcheck failed: $config"
      FAILED=1
    else
      echo "✅ Shellcheck passed: $config"
    fi
  fi
done

exit $FAILED
