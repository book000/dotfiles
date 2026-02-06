# ghq helpers.

# ghqで管理されているリポジトリを選択して移動する関数
gcd() {
  command -v ghq >/dev/null 2>&1 || { echo "ghq not found." >&2; return 1; }
  command -v fzf >/dev/null 2>&1 || { echo "fzf not found." >&2; return 1; }

  local dir
  # fzfを使ってリポジトリを選択
  dir="$(ghq list -p | fzf)" || return 1
  # 選択されたディレクトリが存在すれば移動
  [[ -n "$dir" ]] && { cd "$dir" || return; }
}

# リポジトリを ghq get し、必要に応じて移動や表示を行う関数
# 引数なしの場合は fzf で選択して取得・移動
# 引数ありの場合はそのリポジトリを取得して移動
# write 権限がない場合は自動的に Fork してからクローンする
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
    repo="$(echo "$repos" | grep -v '^$' | sort -u | fzf)" || return 1
  fi

  # URL 形式の正規化
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

  # owner/repo 形式を保持（権限チェック用）
  local repo_name=""
  if [[ "$repo" =~ ^[^/]+/[^/]+$ ]]; then
    repo_name="$repo"
  fi

  # write 権限チェック（owner/repo 形式の場合のみ）
  local original_repo_name=""
  if [[ -n "$repo_name" ]]; then
    echo "Checking write permission for $repo_name..."
    local permission
    if ! permission=$(gh api "repos/$repo_name" --jq '.permissions.push' 2>/dev/null); then
      echo "Failed to check repository permissions. Please check your authentication." >&2
      return 1
    fi

    if [[ "$permission" == "false" ]]; then
      echo "No write permission. Checking if fork exists..."
      local current_user
      if ! current_user=$(gh api user --jq '.login' 2>/dev/null); then
        echo "Failed to get current user. Please check your authentication." >&2
        return 1
      fi

      if [[ -z "$current_user" ]]; then
        echo "Failed to get current user." >&2
        return 1
      fi

      # Fork が既に存在するかチェック（.fork フラグと .parent を確認）
      local fork_check
      fork_check=$(gh api "repos/$current_user/${repo_name#*/}" --jq 'if .fork and .parent.full_name == "'"$repo_name"'" then "true" else "false" end' 2>/dev/null || echo "not_found")

      if [[ "$fork_check" == "not_found" ]]; then
        echo "Creating fork..."
        if ! gh repo fork "$repo_name" --clone=false 2>/dev/null; then
          echo "Failed to create fork." >&2
          return 1
        fi
        echo "Fork created successfully."
      elif [[ "$fork_check" == "true" ]]; then
        echo "Fork already exists."
      else
        echo "Repository $current_user/${repo_name#*/} exists but is not a fork of $repo_name." >&2
        return 1
      fi

      # 元のリポジトリ名を保存（upstream 登録用）
      original_repo_name="$repo_name"

      # Fork のリポジトリに変更
      repo_name="$current_user/${repo_name#*/}"
      echo "Using fork: $repo_name"
    elif [[ "$permission" == "null" ]] || [[ -z "$permission" ]]; then
      echo "Failed to determine repository permissions." >&2
      return 1
    # permission == "true" の場合は write 権限があるため、そのままクローンする
    fi
  fi

  # owner/repo 形式の場合、SSH URL に変換
  if [[ -n "$repo_name" ]]; then
    repo="git@github.com:${repo_name}.git"
  fi

  # リポジトリを取得
  if ! ghq get "$repo"; then
    echo "Failed to clone repository. Please check if ghq is properly configured." >&2
    return 1
  fi

  # クローン先のディレクトリパスを取得
  local repo_path
  if [[ -n "$repo_name" ]]; then
    repo_path=$(ghq list -p -e "$repo_name")
  else
    # URL 形式の場合は ghq list で検索（複数マッチの可能性に注意）
    repo_path=$(ghq list -p "$repo" | head -n1)
    if [[ -z "$repo_path" ]]; then
      echo "Failed to find repository in ghq list." >&2
      return 1
    fi
  fi

  if [[ -z "$repo_path" ]]; then
    echo "Failed to get repository path. Please check if the repository was cloned successfully." >&2
    return 1
  fi

  # ディレクトリに移動
  cd "$repo_path" || return 1

  # Fork した場合は upstream を登録
  if [[ -n "$original_repo_name" ]]; then
    echo "Adding upstream remote..."
    if git remote get-url upstream &>/dev/null; then
      echo "Upstream remote already exists."
    else
      git remote add upstream "git@github.com:${original_repo_name}.git"
      echo "Upstream remote added: $original_repo_name"
    fi
  fi
}

alias gcl='ghc'
