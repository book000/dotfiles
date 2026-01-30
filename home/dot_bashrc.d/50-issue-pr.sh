# GitHub issue を確認して対応し PR を作成する Claude コマンド

# issue を確認して対応し PR を作成する関数
# 引数: issue 番号
issue-pr() {
  command -v gh >/dev/null 2>&1 || { echo "gh not found." >&2; return 1; }
  command -v claude >/dev/null 2>&1 || { echo "claude not found." >&2; return 1; }
  command -v jq >/dev/null 2>&1 || { echo "jq not found." >&2; return 1; }

  local issue_number="$1"

  # 引数のバリデーション
  if [[ -z "$issue_number" ]]; then
    echo "Usage: issue-pr <issue_number>" >&2
    return 1
  fi

  # issue 番号が数値であることを確認
  if ! [[ "$issue_number" =~ ^[0-9]+$ ]]; then
    echo "Error: issue_number must be a number." >&2
    return 1
  fi

  # issue の存在確認と情報取得
  echo "Fetching issue #$issue_number..."
  local issue_info
  if ! issue_info=$(gh issue view "$issue_number" --json title,state,body 2>&1); then
    echo "Error: Failed to fetch issue #$issue_number." >&2
    echo "$issue_info" >&2
    return 1
  fi

  # issue の状態確認
  local issue_state
  issue_state=$(echo "$issue_info" | jq -r '.state')
  if [[ "$issue_state" != "OPEN" ]]; then
    echo "Warning: Issue #$issue_number is not open (state: $issue_state)."
    # 非対話環境では自動的に続行しない
    if [[ ! -t 0 ]]; then
      echo "Error: Cannot confirm in non-interactive mode." >&2
      return 1
    fi
    read -p "Do you want to continue? [y/N]: " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
      return 1
    fi
  fi

  # issue のタイトルと本文を取得
  local issue_title
  local issue_body
  issue_title=$(echo "$issue_info" | jq -r '.title')
  issue_body=$(echo "$issue_info" | jq -r '.body // ""')

  echo "Issue title: $issue_title"

  # デフォルトブランチを取得
  echo "Fetching remote repository..."
  if ! git fetch origin 2>&1; then
    echo "Warning: Failed to fetch from remote. Using local branch." >&2
  fi

  local default_branch
  default_branch=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')
  if [[ -z "$default_branch" ]]; then
    # フォールバック: master または main を試す
    if git show-ref --verify --quiet "refs/remotes/origin/master"; then
      default_branch="master"
    elif git show-ref --verify --quiet "refs/remotes/origin/main"; then
      default_branch="main"
    else
      echo "Error: Could not determine default branch." >&2
      return 1
    fi
  fi

  echo "Default branch: $default_branch"

  # ブランチ名を生成（タイトルから）
  # タイトルを小文字に変換し、スペースをハイフンに置換、英数字とハイフン以外を削除
  local branch_suffix
  branch_suffix=$(echo "$issue_title" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/-\+/-/g' | sed 's/^-\|-$//g' | cut -c1-50)

  # branch_suffix が空の場合（日本語タイトルなど）は issue 番号を使用
  if [[ -z "$branch_suffix" ]]; then
    branch_suffix="issue-${issue_number}"
  fi

  # ブランチのタイプを決定（タイトルから推測）
  local branch_type="feat"
  if echo "$issue_title" | grep -qiE '^(fix|bug)'; then
    branch_type="fix"
  elif echo "$issue_title" | grep -qiE '^(docs|doc)'; then
    branch_type="docs"
  elif echo "$issue_title" | grep -qiE '^(refactor|refactoring)'; then
    branch_type="refactor"
  fi

  local branch_name="${branch_type}/${branch_suffix}"

  echo "Creating branch: $branch_name"

  # ブランチが既に存在するか確認
  if git show-ref --verify --quiet "refs/heads/$branch_name"; then
    echo "Error: Branch $branch_name already exists." >&2
    return 1
  fi

  # デフォルトブランチから最新の状態で新しいブランチを作成
  if ! git checkout -b "$branch_name" "origin/$default_branch" 2>&1; then
    echo "Error: Failed to create branch $branch_name." >&2
    return 1
  fi

  echo "Branch created successfully."

  # Claude CLI を起動して issue の対応を依頼
  echo "Starting Claude CLI to work on issue #$issue_number..."
  echo ""
  echo "========================================"
  printf 'Issue #%s: %s\n' "$issue_number" "$issue_title"
  echo "========================================"
  if [[ -n "$issue_body" ]]; then
    printf '%s\n' "$issue_body"
    echo "========================================"
  fi
  echo ""

  # Claude CLI に渡すプロンプトを作成
  local claude_prompt="issue#${issue_number}に対応してprを作成して"

  # Claude CLI を起動
  claude "$claude_prompt"
}
