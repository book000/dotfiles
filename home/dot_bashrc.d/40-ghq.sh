# ghq helpers.

# ghqで管理されているリポジトリを選択して移動する関数
gcd() {
  command -v ghq >/dev/null 2>&1 || { echo "ghq not found." >&2; return 1; }
  command -v fzf >/dev/null 2>&1 || { echo "fzf not found." >&2; return 1; }

  local dir
  # fzfを使ってリポジトリを選択
  dir="$(ghq list -p | fzf --prompt='Repo> ' --height=40% --reverse)" || return 1
  # 選択されたディレクトリが存在すれば移動
  [[ -n "$dir" ]] && cd "$dir"
}

# リポジトリを ghq get し、必要に応じて移動や表示を行う関数
# 引数なしの場合は fzf で選択して取得・移動
# 引数ありの場合はそのリポジトリを取得して移動
ghc() {
  command -v ghq >/dev/null 2>&1 || { echo "ghq not found." >&2; return 1; }
  command -v fzf >/dev/null 2>&1 || { echo "fzf not found." >&2; return 1; }
  command -v gh >/dev/null 2>&1 || { echo "gh not found." >&2; return 1; }

  local repo="$1"
  # 引数がない場合は gh コマンドでターゲットのリポジトリ一覧を取得し、fzf で選択させる
  if [[ -z "$repo" ]]; then
    local targets=("book000" "tomacheese" "jaoafa")
    local repos=""
    for target in "${targets[@]}"; do
      if list=$(gh repo list "$target" --limit 1000 --json nameWithOwner --jq '.[].nameWithOwner' 2>/dev/null); then
        repos+="$list"$'\n'
      fi
    done
    repo="$(echo "$repos" | grep -v '^$' | sort -u | fzf --prompt='Repo> ' --height=40% --reverse)" || return 1
  fi

  # URL形式の正規化
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

  # リポジトリを取得し、そのディレクトリ内のシェルを起動（または移動）
  ghq get --look "$repo"
}

alias gcl='ghc'
