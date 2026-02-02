#!/bin/bash
# Git バージョンチェック
# zdiff3 は Git 2.35.0 で導入されたため、それ以上のバージョンが必要

# Git が存在するかチェック
command -v git >/dev/null 2>&1 || return 0

# バージョン取得
__git_version=$(git --version 2>/dev/null | sed -E 's/git version ([0-9]+\.[0-9]+\.[0-9]+).*/\1/')

# バージョンが取得できなかった場合はスキップ
[ -z "$__git_version" ] && return 0

# バージョン比較関数
__version_ge() {
  local v1="$1"
  local v2="$2"

  if [ "$(printf '%s\n%s' "$v1" "$v2" | sort -V | tail -n1)" = "$v1" ]; then
    return 0
  else
    return 1
  fi
}

# バージョンチェック（2.35.0 未満の場合は警告）
if ! __version_ge "$__git_version" "2.35.0"; then
  echo "⚠️  WARNING: Git version 2.35.0 or higher is required (current: $__git_version)" >&2
  echo "⚠️  zdiff3 merge conflict style requires Git 2.35.0+" >&2
  echo "" >&2

  # Ubuntu/Debian の場合は PPA の案内
  if [ -f /etc/os-release ]; then
    # shellcheck source=/dev/null
    . /etc/os-release
    if [ "$ID" = "ubuntu" ] || [ "$ID" = "debian" ]; then
      echo "   On Ubuntu/Debian, install the latest Git from PPA:" >&2
      echo "     sudo add-apt-repository ppa:git-core/ppa" >&2
      echo "     sudo apt update" >&2
      echo "     sudo apt install git" >&2
    fi
  fi
  echo "" >&2
fi

# クリーンアップ
unset __git_version
unset -f __version_ge
