#!/bin/bash
# ==============================================================================
# dotfiles インストーラー
# ==============================================================================
# 使用方法:
#   推奨 (3 ステップインストール):
#     curl -fsSL https://raw.githubusercontent.com/book000/dotfiles/master/install.sh -o /tmp/install.sh
#     less /tmp/install.sh  # スクリプトを確認
#     bash /tmp/install.sh
#
#   ワンライナー (自己責任):
#     curl -fsSL https://raw.githubusercontent.com/book000/dotfiles/master/install.sh | bash
#
#   オプション:
#     --dry-run          実際のコマンドを実行せず、ログのみ出力
#     --skip-apt         apt-get によるパッケージインストールをスキップ
#     --skip-gh          gh CLI のインストールをスキップ
#     --skip-ghq         ghq のインストールをスキップ
#     --skip-mkwork      mkwork のインストールをスキップ
#     --skip-interactive 対話的な確認をスキップ (CI 用)
#     --help             ヘルプを表示
# ==============================================================================

set -e
set -u
set -o pipefail

# パラメータ変数
DRY_RUN=0
SKIP_APT=0
SKIP_GH=0
SKIP_GHQ=0
SKIP_MKWORK=0
SKIP_INTERACTIVE=0

# ヘルプメッセージを表示する関数
# このスクリプトの使用方法とオプションの説明を出力する
show_help() {
  cat <<EOF
使用方法: $0 [OPTIONS]

OPTIONS:
  --dry-run          実際のコマンドを実行せず、ログのみ出力
  --skip-apt         apt-get によるパッケージインストールをスキップ
  --skip-gh          gh CLI のインストールをスキップ
  --skip-ghq         ghq のインストールをスキップ
  --skip-mkwork      mkwork のインストールをスキップ
  --skip-interactive 対話的な確認をスキップ (CI 用)
  --help             このヘルプを表示

例:
  # 通常のインストール
  bash install.sh

  # CI 用の非対話モード (apt インストールのみスキップ)
  bash install.sh --skip-interactive --skip-apt --skip-gh --skip-ghq --skip-mkwork

  # ドライラン
  bash install.sh --dry-run
EOF
}

# パラメータパース
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --skip-apt)
      SKIP_APT=1
      shift
      ;;
    --skip-gh)
      SKIP_GH=1
      shift
      ;;
    --skip-ghq)
      SKIP_GHQ=1
      shift
      ;;
    --skip-mkwork)
      SKIP_MKWORK=1
      shift
      ;;
    --skip-interactive)
      SKIP_INTERACTIVE=1
      shift
      ;;
    --help)
      show_help
      exit 0
      ;;
    *)
      echo "❌ Unknown option: $1"
      show_help
      exit 1
      ;;
  esac
done

# 非対話モードのための環境変数を設定 (後方互換性のため)
if [[ "$SKIP_INTERACTIVE" == "1" ]]; then
  NO_INTERACTIVE=1
fi

# カラー出力用の定数
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[0;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'  # No Color

# ログ出力関数
log_debug() {
  [[ "${LOG_LEVEL:-INFO}" == "DEBUG" ]] && echo -e "${BLUE}[DEBUG]${NC} $1"
}

log_info() {
  echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
  echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
  echo -e "${RED}[ERROR]${NC} $1" >&2
}

# コマンドを実行する関数 (DRY_RUN モード対応)
# DRY_RUN=1 の場合は実行せずログ出力のみ行う
# それ以外の場合は渡された引数をそのままコマンドとして実行する
# 引数: 実行するコマンドとその引数
run_command() {
  if [[ "$DRY_RUN" == "1" ]]; then
    log_info "[DRY RUN] $*"
    return 0
  fi
  "$@"
}

# クリーンアップ処理
cleanup() {
  local exit_code=$?
  if [[ $exit_code -ne 0 ]]; then
    log_error "Installation failed with exit code: $exit_code"
    log_error "Please check the log above for details"
  fi
}
trap cleanup EXIT

# バージョン比較関数
# 引数: version_ge <version1> <version2>
# 戻り値: version1 >= version2 の場合 0、それ以外は 1
version_ge() {
  local v1="$1"
  local v2="$2"

  # sort -V を使ってバージョンをソート
  # 最大のバージョンが v1 と一致すれば v1 >= v2
  if [ "$(printf '%s\n%s' "$v1" "$v2" | sort -V | tail -n1)" = "$v1" ]; then
    return 0
  else
    return 1
  fi
}

# 環境チェック
check_environment() {
  log_info "環境をチェックしています..."

  # OS 判定
  case "$OSTYPE" in
    linux-gnu*)
      OS="linux"
      # ディストリビューション判定
      if [[ -f /etc/os-release ]]; then
        # shellcheck source=/dev/null
        source /etc/os-release
        DISTRO="$ID"

        # サポート対象の確認
        case "$DISTRO" in
          ubuntu|debian)
            log_info "サポート対象のディストリビューションを検出: $DISTRO"
            ;;
          *)
            log_error "Unsupported distribution: $DISTRO"
            log_error "This script supports only Ubuntu and Debian"
            return 1
            ;;
        esac
      else
        log_error "Cannot detect Linux distribution"
        return 1
      fi
      ;;
    darwin*)
      log_error "macOS is not supported yet"
      return 1
      ;;
    msys*|cygwin*)
      log_error "Windows is not supported yet"
      return 1
      ;;
    *)
      log_error "Unsupported OS: $OSTYPE"
      return 1
      ;;
  esac

  # アーキテクチャ判定
  ARCH=$(uname -m)
  case "$ARCH" in
    x86_64)
      ARCH="amd64"
      ;;
    aarch64|arm64)
      ARCH="arm64"
      ;;
    *)
      log_error "Unsupported architecture: $ARCH"
      return 1
      ;;
  esac

  log_info "検出された OS: $OS, アーキテクチャ: $ARCH"

  # 必須コマンドの確認
  for cmd in curl git; do
    if ! command -v "$cmd" &> /dev/null; then
      log_error "Required command not found: $cmd"
      return 1
    fi
  done

  # Git バージョンチェック（2.35.0 以上が必要）
  log_info "Git バージョンをチェックしています..."
  local git_version
  git_version=$(git --version 2>/dev/null | sed -E 's/git version ([0-9]+\.[0-9]+\.[0-9]+).*/\1/')

  if [[ -z "$git_version" ]]; then
    log_error "Failed to detect Git version"
    return 1
  fi

  if ! version_ge "$git_version" "2.35.0"; then
    log_error "Git version 2.35.0 or higher is required (current: $git_version)"
    log_error "zdiff3 merge conflict style requires Git 2.35.0+"
    log_error ""

    # Ubuntu/Debian の場合は PPA の案内
    if [[ "$DISTRO" == "ubuntu" ]] || [[ "$DISTRO" == "debian" ]]; then
      log_error "On Ubuntu/Debian, install the latest Git from PPA:"
      log_error "  sudo add-apt-repository ppa:git-core/ppa"
      log_error "  sudo apt update"
      log_error "  sudo apt install git"
    fi

    return 1
  fi

  log_info "Git version: $git_version (OK)"
}

# SSH 設定の退避
backup_ssh_config() {
  log_info "SSH 設定をチェックしています..."

  local ssh_dir="$HOME/.ssh"
  local ssh_config="$ssh_dir/config"
  local backup_dir="$ssh_dir/conf.d"
  local backup_file="$backup_dir/00-prev-config.conf"

  # ~/.ssh ディレクトリのパーミッションを 700 に設定
  if [[ -d "$ssh_dir" ]]; then
    chmod 700 "$ssh_dir"
  else
    mkdir -p "$ssh_dir"
    chmod 700 "$ssh_dir"
  fi

  if [[ -f "$ssh_config" ]]; then
    if [[ -f "$backup_file" ]]; then
      log_warn "バックアップファイルが既に存在します: $backup_file (スキップ)"
    else
      mkdir -p "$backup_dir"
      chmod 700 "$backup_dir"

      # 既存の config を退避
      mv "$ssh_config" "$backup_file"
      chmod 600 "$backup_file"

      log_info "SSH 設定をバックアップしました: $backup_file"
      log_info "chezmoi apply で新しい config が作成されます"
    fi
  else
    log_info "SSH 設定が見つかりません (スキップ)"
  fi
}

# chezmoi のインストール
install_chezmoi() {
  log_info "chezmoi を ~/.local/bin にインストールしています..."

  if command -v chezmoi &> /dev/null; then
    log_warn "chezmoi は既にインストールされています: $(command -v chezmoi)"
  else
    # ~/.local/bin が存在しない場合は作成
    mkdir -p "$HOME/.local/bin"

    # chezmoi を ~/.local/bin にインストール（ホームディレクトリから実行）
    (cd "$HOME" && sh -c "$(curl -fsLS https://get.chezmoi.io/lb)")

    log_info "chezmoi が正常にインストールされました"
  fi

  # PATH の確認と案内
  if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
    log_warn "$HOME/.local/bin が PATH に含まれていません"
    log_warn "シェル設定ファイルに以下の行を追加してください:"
    log_warn "  export PATH=\"\$HOME/.local/bin:\$PATH\""

    # 現在のセッションでは一時的に追加
    export PATH="$HOME/.local/bin:$PATH"
  fi

  # init のみ実行（apply は後で）
  log_info "chezmoi を初期化しています (apply なし)..."
  chezmoi init book000 || { log_error "Failed to initialize chezmoi"; return 1; }
}

# apt パッケージのインストール
install_apt_packages() {
  if [[ "$SKIP_APT" == "1" ]]; then
    log_info "apt パッケージのインストールをスキップします (--skip-apt)"
    return 0
  fi

  log_info "apt パッケージをインストールしています..."

  # パッケージのリスト
  local packages=(
    "curl"
    "git"
    "unzip"
    "zsh"
    "bash"
    "tmux"
    "vim"
    "fzf"
    "powerline"
    "jq"
  )

  # apt update
  log_info "パッケージリストを更新しています..."
  run_command sudo apt update

  # パッケージのインストール
  log_info "パッケージをインストールしています: ${packages[*]}"
  run_command sudo apt install -y "${packages[@]}"
}

# gh CLI のインストール
install_gh_cli() {
  if [[ "$SKIP_GH" == "1" ]]; then
    log_info "gh CLI のインストールをスキップします (--skip-gh)"
    return 0
  fi

  log_info "GitHub CLI (gh) をインストールしています..."

  if command -v gh &> /dev/null; then
    log_warn "gh は既にインストールされています ($(gh --version | head -n1))"
    return 0
  fi

  # GitHub CLI 公式リポジトリの追加
  if ! command -v curl &> /dev/null; then
    run_command sudo apt update
    run_command sudo apt install curl -y
  fi

  run_command curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg -o /tmp/githubcli-archive-keyring.gpg
  run_command sudo dd if=/tmp/githubcli-archive-keyring.gpg of=/usr/share/keyrings/githubcli-archive-keyring.gpg
  run_command sudo chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg

  if [[ "$DRY_RUN" == "1" ]]; then
    log_info "[DRY RUN] echo \"deb [arch=\$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main\" | sudo tee /etc/apt/sources.list.d/github-cli.list"
  else
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
  fi

  run_command sudo apt update
  run_command sudo apt install gh -y

  if [[ "$DRY_RUN" != "1" ]]; then
    log_info "gh が正常にインストールされました ($(gh --version | head -n1))"
  fi
}

# ghq のインストール
install_ghq() {
  if [[ "$SKIP_GHQ" == "1" ]]; then
    log_info "ghq のインストールをスキップします (--skip-ghq)"
    return 0
  fi

  log_info "ghq をインストールしています..."

  if command -v ghq &> /dev/null; then
    log_warn "ghq は既にインストールされています"
    return 0
  fi

  # パッケージマネージャで試行
  if command -v apt &> /dev/null; then
    log_info "apt で ghq をインストールしています..."
    if [[ "$DRY_RUN" == "1" ]]; then
      log_info "[DRY RUN] apt で ghq のインストールをスキップし、GitHub Release からのインストールに進みます"
    else
      if run_command sudo apt install -y ghq 2>/dev/null; then
        log_info "ghq が apt からインストールされました"
        return 0
      else
        log_warn "apt で ghq が見つかりませんでした。GitHub Release からダウンロードします"
      fi
    fi
  fi

  # GitHub Release から最新版を取得
  log_info "GitHub Release から最新版を取得しています..."

  local version
  local api_response
  api_response=$(curl -fsSL https://api.github.com/repos/x-motemen/ghq/releases/latest)

  # jq が利用可能なら JSON を安全にパースする
  if command -v jq &> /dev/null; then
    version=$(printf '%s\n' "$api_response" | jq -r '.tag_name' | sed -E 's/^v//')
  else
    # jq が利用できない場合は従来の grep / sed にフォールバックする
    log_warn "jq is not installed. Falling back to grep/sed for version parsing"
    version=$(printf '%s\n' "$api_response" | grep '"tag_name":' | sed -E 's/.*"v([^"]+)".*/\1/')
  fi

  if [[ -z "$version" || "$version" == "null" ]]; then
    log_error "Failed to parse latest version from GitHub API"
    return 1
  fi

  log_info "最新バージョン: v$version"

  # ダウンロード URL
  local os
  os=$(uname -s | tr '[:upper:]' '[:lower:]')
  local download_url="https://github.com/x-motemen/ghq/releases/download/v${version}/ghq_${os}_${ARCH}.zip"

  log_info "ダウンロード URL: $download_url"

  # 一時ディレクトリでダウンロード
  local temp_dir
  temp_dir=$(mktemp -d)

  # 一時ディレクトリのクリーンアップを設定
  trap 'rm -rf "$temp_dir"' RETURN

  if [[ ! -d "$temp_dir" ]]; then
    log_error "Failed to create temporary directory"
    return 1
  fi

  cd "$temp_dir" || {
    log_error "Failed to change directory to temporary directory"
    return 1
  }

  # ghq のアーカイブをダウンロード
  if ! curl -L -o ghq.zip "$download_url"; then
    log_error "Failed to download ghq archive"
    cd - > /dev/null || true
    return 1
  fi

  # ダウンロードしたアーカイブを展開
  if ! unzip -q ghq.zip; then
    log_error "Failed to unzip ghq archive"
    cd - > /dev/null || true
    return 1
  fi

  # 展開後の ghq バイナリを特定
  local ghq_binary
  ghq_binary=$(find . -maxdepth 2 -type f -name ghq -print -quit)

  if [[ -z "$ghq_binary" ]]; then
    log_error "ghq binary not found after extraction"
    cd - > /dev/null || true
    return 1
  fi

  # ~/.local/bin にインストール
  mkdir -p "$HOME/.local/bin"
  mv "$ghq_binary" "$HOME/.local/bin/ghq"
  chmod +x "$HOME/.local/bin/ghq"

  cd - > /dev/null

  log_info "ghq が正常にインストールされました"
}

# mkwork のインストール
install_mkwork() {
  if [[ "$SKIP_MKWORK" == "1" ]]; then
    log_info "mkwork のインストールをスキップします (--skip-mkwork)"
    return 0
  fi

  log_info "mkwork をインストールしています..."

  local mkwork_script="$HOME/.local/share/mkwork/mkwork.sh"

  if [[ -f "$mkwork_script" ]]; then
    log_warn "mkwork は既にインストールされています"
  else
    log_info "mkwork をダウンロードしています..."

    # インストール先ディレクトリを作成
    mkdir -p "$HOME/.local/share/mkwork"

    # mkwork.sh をダウンロード
    curl -fsSL https://github.com/book000/mkwork/releases/latest/download/mkwork.sh -o "$mkwork_script"
    chmod +x "$mkwork_script"

    log_info "mkwork が正常にインストールされました"
  fi

  # work_root の設定
  local config_file="$HOME/.config/mkwork/config"

  if [[ -f "$config_file" ]]; then
    log_warn "mkwork の設定ファイルが既に存在します"
  else
    mkdir -p "$HOME/.config/mkwork"

    # 非対話モードでない場合は入力を受け付ける
    if [[ "${NO_INTERACTIVE:-0}" != "1" ]]; then
      local work_root
      read -r -p "mkwork の作業ディレクトリ [~/work]: " work_root
      work_root="${work_root:-$HOME/work}"
      echo "work_root=$work_root" > "$config_file"
      log_info "mkwork の設定を作成しました: work_root=$work_root"
    else
      # 非対話モードではデフォルト値を使用
      echo "work_root=$HOME/work" > "$config_file"
      log_info "mkwork の設定を作成しました (デフォルト): work_root=$HOME/work"
    fi
  fi
}

# .gitconfig.local のセットアップ
setup_gitconfig_local() {
  log_info ".gitconfig.local をセットアップしています..."

  local gitconfig_local="$HOME/.gitconfig.local"

  if [[ -f "$gitconfig_local" ]]; then
    log_warn ".gitconfig.local が既に存在します"

    if [[ "${NO_INTERACTIVE:-0}" != "1" ]]; then
      local confirm
      read -r -p "上書きしますか? [y/N]: " confirm
      if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        log_info ".gitconfig.local のセットアップをスキップしました"
        return 0
      fi
    else
      log_info ".gitconfig.local のセットアップをスキップしました"
      return 0
    fi
  fi

  # 非対話モードでない場合は入力を受け付ける
  if [[ "${NO_INTERACTIVE:-0}" != "1" ]]; then
    # Git user 設定
    echo "[user]" > "$gitconfig_local"

    local git_name
    read -r -p "Git ユーザー名: " git_name
    echo "    name = $git_name" >> "$gitconfig_local"

    local git_email
    read -r -p "Git メールアドレス: " git_email
    echo "    email = $git_email" >> "$gitconfig_local"

    # ghq.root 設定
    echo "" >> "$gitconfig_local"
    echo "[ghq]" >> "$gitconfig_local"

    local ghq_root
    read -r -p "ghq ルートディレクトリ [~/repos]: " ghq_root
    ghq_root="${ghq_root:-$HOME/repos}"
    echo "    root = $ghq_root" >> "$gitconfig_local"

    log_info ".gitconfig.local を作成しました"
  else
    # 非対話モードでは .gitconfig.local.example をコピー
    local example_file="$HOME/.gitconfig.local.example"

    # $HOME に .gitconfig.local.example が存在しない場合は chezmoi のソースディレクトリから取得
    if [[ ! -f "$example_file" ]]; then
      local chezmoi_source
      chezmoi_source=$(chezmoi source-path 2>/dev/null || echo "$HOME/.local/share/chezmoi")
      local source_example="$chezmoi_source/home/dot_gitconfig.local.example"

      if [[ -f "$source_example" ]]; then
        cp "$source_example" "$example_file"
        log_info "chezmoi ソースから .gitconfig.local.example をコピーしました"
      else
        # chezmoi ソースにも存在しない場合はデフォルト値で作成
        log_warn "非対話モード: .gitconfig.local.example が見つかりません。デフォルト値で作成します"
        cat > "$example_file" << 'EOF'
# =========================================
# Git user configuration
# =========================================
# このファイルを ~/.gitconfig.local にコピーして使用してください
#
# 使い方:
#   cp ~/.gitconfig.local.example ~/.gitconfig.local
#   vi ~/.gitconfig.local  # 名前とメールアドレスを編集
# =========================================

[user]
    name = Your Name
    email = your.email@example.com

[ghq]
    root = ~/repos

EOF
        log_info "デフォルトの .gitconfig.local.example を作成しました"
      fi
    fi

    # .gitconfig.local.example をコピー
    cp "$example_file" "$gitconfig_local"
    log_warn "非対話モード: .gitconfig.local.example をコピーしました"
    log_warn "後で手動で編集してください: $gitconfig_local"
  fi
}

# .env のセットアップ
setup_env() {
  log_info ".env をセットアップしています..."

  local env_file="$HOME/.env"

  if [[ -f "$env_file" ]]; then
    log_warn ".env が既に存在します"

    if [[ "${NO_INTERACTIVE:-0}" != "1" ]]; then
      local confirm
      read -r -p "上書きしますか? [y/N]: " confirm
      if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        log_info ".env のセットアップをスキップしました"
        return 0
      fi
    else
      log_info ".env のセットアップをスキップしました"
      return 0
    fi
  fi

  # 非対話モードの場合は後で .env.example から自動コピー
  if [[ "${NO_INTERACTIVE:-0}" == "1" ]]; then
    log_info ".env は非対話モードのためここでは作成しません (chezmoi apply 前に .env.example から自動コピーされます)"
    return 0
  fi

  # 対話モードの場合は Discord Webhook URL などを入力
  cat > "$env_file" <<'EOF'
# =========================================
# chezmoi dotfiles 環境変数設定
# =========================================

EOF

  # Claude completion-notify
  echo "# -----------------------------------------" >> "$env_file"
  echo "# Discord Webhooks - Claude completion-notify" >> "$env_file"
  echo "# -----------------------------------------" >> "$env_file"

  local webhook_url
  read -r -p "Claude completion-notify の Discord Webhook URL (空欄でスキップ): " webhook_url
  if [[ -n "$webhook_url" ]]; then
    echo "DISCORD_CLAUDE_WEBHOOK=\"$webhook_url\"" >> "$env_file"
  else
    echo "DISCORD_CLAUDE_WEBHOOK=\"\"" >> "$env_file"
  fi

  local mention_user_id
  read -r -p "メンションする Discord ユーザー ID (空欄でスキップ): " mention_user_id
  echo "DISCORD_CLAUDE_MENTION_USER_ID=\"$mention_user_id\"" >> "$env_file"
  echo "" >> "$env_file"

  # Claude limit-unlocked
  echo "# -----------------------------------------" >> "$env_file"
  echo "# Discord Webhooks - Claude limit-unlocked" >> "$env_file"
  echo "# -----------------------------------------" >> "$env_file"

  read -r -p "Claude limit-unlocked の Discord Webhook URL (空欄でスキップ): " webhook_url
  if [[ -n "$webhook_url" ]]; then
    echo "DISCORD_CLAUDE_LIMIT_WEBHOOK=\"$webhook_url\"" >> "$env_file"
  else
    echo "DISCORD_CLAUDE_LIMIT_WEBHOOK=\"\"" >> "$env_file"
  fi

  read -r -p "メンションする Discord ユーザー ID (空欄でスキップ): " mention_user_id
  echo "DISCORD_CLAUDE_LIMIT_MENTION_USER_ID=\"$mention_user_id\"" >> "$env_file"
  echo "" >> "$env_file"

  # Gemini
  echo "# -----------------------------------------" >> "$env_file"
  echo "# Discord Webhooks - Gemini" >> "$env_file"
  echo "# -----------------------------------------" >> "$env_file"

  read -r -p "Gemini の Discord Webhook URL (空欄でスキップ): " webhook_url
  if [[ -n "$webhook_url" ]]; then
    echo "DISCORD_GEMINI_WEBHOOK=\"$webhook_url\"" >> "$env_file"
  else
    echo "DISCORD_GEMINI_WEBHOOK=\"\"" >> "$env_file"
  fi

  read -r -p "メンションする Discord ユーザー ID (空欄でスキップ): " mention_user_id
  echo "DISCORD_GEMINI_MENTION_USER_ID=\"$mention_user_id\"" >> "$env_file"

  # .env ファイルのパーミッションを 600 に設定（センシティブ情報を含むため）
  chmod 600 "$env_file"

  log_info ".env を作成しました"
}

# 非対話モードで .env.example から .env をコピー
copy_env_if_needed() {
  local env_file="$HOME/.env"
  local example_file="$HOME/.env.example"

  if [[ ! -f "$env_file" ]] && [[ -f "$example_file" ]]; then
    cp "$example_file" "$env_file"
    # .env ファイルのパーミッションを 600 に設定（センシティブ情報を含むため）
    chmod 600 "$env_file"
    log_info ".env を .env.example からコピーしました"
    log_warn "Discord Webhook URL などを設定してください: $env_file"
  fi
}

# chezmoi apply を実行
apply_chezmoi() {
  log_info "必要な設定ファイルの確認..."

  # .gitconfig.local と .env の存在確認（警告のみ）
  if [[ ! -f "$HOME/.gitconfig.local" ]]; then
    log_warn ".gitconfig.local が見つかりません。テンプレート展開でエラーが発生する可能性があります"
  fi

  if [[ ! -f "$HOME/.env" ]]; then
    log_warn ".env が見つかりません。テンプレート展開でエラーが発生する可能性があります"
  fi

  log_info "chezmoi の設定を適用しています..."
  run_command chezmoi apply
  log_info "chezmoi の設定が正常に適用されました"

  # chezmoi apply 後にパーミッションを再設定
  local ssh_dir="$HOME/.ssh"
  local ssh_conf_d="$ssh_dir/conf.d"
  local ssh_config="$ssh_dir/config"

  if [[ -d "$ssh_dir" ]]; then
    chmod 700 "$ssh_dir"
  fi

  if [[ -d "$ssh_conf_d" ]]; then
    chmod 700 "$ssh_conf_d"
  fi

  if [[ -f "$ssh_config" ]]; then
    chmod 600 "$ssh_config"
  fi
}

# メイン処理
main() {
  log_info "dotfiles のインストールを開始します..."
  log_info ""

  check_environment
  backup_ssh_config
  install_chezmoi
  install_apt_packages
  install_gh_cli
  install_ghq
  install_mkwork
  setup_gitconfig_local
  setup_env
  copy_env_if_needed  # chezmoi apply 前に .env をコピー（テンプレート展開エラー回避）
  apply_chezmoi

  log_info ""
  log_info "✅ インストールが正常に完了しました!"
  log_info ""
  log_info "次のステップ:"
  log_info "  1. シェルを再起動するか、以下のコマンドを実行してください:"
  log_info "     source ~/.bashrc  # または source ~/.zshrc"
  log_info "  2. .env ファイルを編集して、Discord Webhook URL などを設定してください:"
  log_info "     vim ~/.env"
  log_info "  3. ~/.local/bin が PATH に含まれていない場合は、シェル設定ファイルに追加してください:"
  log_info "     export PATH=\"\$HOME/.local/bin:\$PATH\""
}

main "$@"
