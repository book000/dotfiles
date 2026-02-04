#!/bin/bash
# bash -n による構文チェック

set -euo pipefail

echo "Checking bash syntax..."

FAILED=0

# シェル断片を含む全スクリプトを構文チェック
while IFS= read -r -d '' script; do
  # シェバンの有無と種類を確認
  if head -n 1 "$script" | grep -qE '^#!(.*/)?(bash|sh)'; then
    # bash / sh の shebang がある場合
    if ! bash -n "$script"; then
      echo "❌ Syntax error: $script"
      FAILED=1
    else
      echo "✅ Syntax OK: $script"
    fi
  elif head -n 1 "$script" | grep -qE '^#!(.*/)?zsh'; then
    # zsh の shebang がある場合
    if command -v zsh &> /dev/null; then
      if ! zsh -n "$script"; then
        echo "❌ Syntax error: $script"
        FAILED=1
      else
        echo "✅ Syntax OK: $script"
      fi
    else
      # zsh がない環境では bash として構文チェック
      if ! bash -n "$script"; then
        echo "❌ Syntax error (as bash): $script"
        FAILED=1
      else
        echo "✅ Syntax OK (as bash): $script"
      fi
    fi
  else
    # シェバンがない場合は拡張子で判定
    if [[ "$script" == *.zsh ]] && command -v zsh &> /dev/null; then
      # .zsh 拡張子のファイルは zsh として構文チェック
      if ! zsh -n "$script"; then
        echo "❌ Syntax error: $script"
        FAILED=1
      else
        echo "✅ Syntax OK: $script"
      fi
    else
      # それ以外は bash として構文チェック
      if ! bash -n "$script"; then
        echo "❌ Syntax error (as bash): $script"
        FAILED=1
      else
        echo "✅ Syntax OK (as bash): $script"
      fi
    fi
  fi
done < <(find . -type f \( -name "*.sh" -o -name "executable_*" \) \
  -not -path "./.bare/*" \
  -not -path "./bin/*" \
  -print0)

# 主要な設定ファイルも bash として構文チェック
for config in home/dot_bashrc home/dot_bash_profile; do
  if [ -f "$config" ]; then
    if ! bash -n "$config"; then
      echo "❌ Syntax error: $config"
      FAILED=1
    else
      echo "✅ Syntax OK: $config"
    fi
  fi
done

# zsh 設定ファイルの構文チェック (zsh が利用可能な場合のみ)
if command -v zsh &> /dev/null; then
  # dot_zshrc と dot_zshrc.d/*.zsh をチェック
  for config in home/dot_zshrc home/dot_zshrc.d/*.zsh; do
    if [ -f "$config" ]; then
      if ! zsh -n "$config"; then
        echo "❌ Syntax error: $config"
        FAILED=1
      else
        echo "✅ Syntax OK: $config"
      fi
    fi
  done
fi

exit $FAILED
