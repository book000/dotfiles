# ghq helpers.
gcd() {
  command -v ghq >/dev/null 2>&1 || { echo "ghq not found." >&2; return 1; }
  command -v fzf >/dev/null 2>&1 || { echo "fzf not found." >&2; return 1; }

  local dir
  dir="$(ghq list -p | fzf --prompt='Repo> ' --height=40% --reverse)" || return 1
  [[ -n "$dir" ]] && cd "$dir"
}

ghc() {
  command -v ghq >/dev/null 2>&1 || { echo "ghq not found." >&2; return 1; }

  local repo="$1"
  if [[ -z "$repo" ]]; then
    command -v fzf >/dev/null 2>&1 || { echo "fzf not found." >&2; return 1; }
    repo="$(ghq list | fzf --prompt='Repo (owner/name or URL)> ' --height=40% --reverse)" || return 1
  fi

  if [[ "$repo" == https://github.com/* ]]; then
    repo="${repo#https://github.com/}"
  elif [[ "$repo" == http://github.com/* ]]; then
    repo="${repo#http://github.com/}"
  elif [[ "$repo" == git@github.com:* ]]; then
    repo="${repo#git@github.com:}"
  elif [[ "$repo" == github.com/* ]]; then
    repo="${repo#github.com/}"
  fi

  repo="${repo%.git}"
  repo="${repo%/}"

  # owner/repo 形式の場合、SSH URLに変換
  if [[ "$repo" =~ ^[^/]+/[^/]+$ ]]; then
    repo="git@github.com:${repo}.git"
  fi

  ghq get --look "$repo"
}

alias gcl='ghc'
