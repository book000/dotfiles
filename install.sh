#!/bin/bash
# ==============================================================================
# dotfiles インストーラー
# ==============================================================================
# 使用方法:
#   推奨 (2 ステップ検証):
#     curl -fsSL https://raw.githubusercontent.com/book000/dotfiles/master/install.sh -o /tmp/install.sh
#     less /tmp/install.sh  # スクリプトを確認
#     bash /tmp/install.sh
#
#   ワンライナー (自己責任):
#     curl -fsSL https://raw.githubusercontent.com/book000/dotfiles/master/install.sh | bash
# ==============================================================================

set -e
set -u
set -o pipefail

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

# クリーンアップ処理
cleanup() {
  local exit_code=$?
  if [[ $exit_code -ne 0 ]]; then
    log_error "Installation failed with exit code: $exit_code"
    log_error "Please check the log above for details"
  fi
}
trap cleanup EXIT

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
}

# SSH 設定の退避
backup_ssh_config() {
  log_info "SSH 設定をチェックしています..."

  local ssh_config="$HOME/.ssh/config"
  local backup_dir="$HOME/.ssh/conf.d"
  local backup_file="$backup_dir/00-prev-config.conf"

  if [[ -f "$ssh_config" ]]; then
    if [[ -f "$backup_file" ]]; then
      log_warn "バックアップファイルが既に存在します: $backup_file (スキップ)"
    else
      mkdir -p "$backup_dir"
      chmod 700 "$backup_dir"

      # 既存の config を退避
      mv "$ssh_config" "$backup_file"
      chmod 600 "$backup_file"

      # 新しい config を作成し、Include を追加
      cat > "$ssh_config" <<EOF
# dotfiles インストーラーにより生成
Include conf.d/*.conf
EOF
      chmod 600 "$ssh_config"

      log_info "SSH 設定をバックアップしました: $backup_file"
      log_info "Include ディレクティブを追加しました: $ssh_config"
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

    # chezmoi を ~/.local/bin にインストール
    sh -c "$(curl -fsLS get.chezmoi.io/lb)"

    log_info "chezmoi が正常にインストールされました"
  fi

  # PATH の確認と案内
  if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
    log_warn "~/.local/bin が PATH に含まれていません"
    log_warn "シェル設定ファイルに以下の行を追加してください:"
    log_warn "  export PATH=\"\$HOME/.local/bin:\$PATH\""

    # 現在のセッションでは一時的に追加
    export PATH="$HOME/.local/bin:$PATH"
  fi

  # init のみ実行（apply は後で）
  log_info "chezmoi を初期化しています (apply なし)..."
  chezmoi init book000
}

# apt パッケージのインストール
install_apt_packages() {
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
  )

  # apt update
  log_info "パッケージリストを更新しています..."
  sudo apt update

  # パッケージのインストール
  log_info "パッケージをインストールしています: ${packages[*]}"
  # shellcheck disable=SC2068
  sudo apt install -y ${packages[@]}
}

# gh CLI のインストール
install_gh_cli() {
  log_info "GitHub CLI (gh) をインストールしています..."

  if command -v gh &> /dev/null; then
    log_warn "gh は既にインストールされています ($(gh --version | head -n1))"
    return 0
  fi

  # GitHub CLI 公式リポジトリの追加
  if ! command -v curl &> /dev/null; then
    sudo apt update && sudo apt install curl -y
  fi

  curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
  sudo chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
  sudo apt update
  sudo apt install gh -y

  log_info "gh が正常にインストールされました ($(gh --version | head -n1))"
}

# ghq のインストール
install_ghq() {
  log_info "ghq をインストールしています..."

  if command -v ghq &> /dev/null; then
    log_warn "ghq は既にインストールされています"
    return 0
  fi

  # パッケージマネージャで試行
  if command -v apt &> /dev/null; then
    log_info "apt で ghq をインストールしています..."
    if sudo apt install -y ghq 2>/dev/null; then
      log_info "ghq が apt からインストールされました"
      return 0
    else
      log_warn "apt で ghq が見つかりませんでした。GitHub Release からダウンロードします"
    fi
  fi

  # GitHub Release から最新版を取得
  log_info "GitHub Release から最新版を取得しています..."

  local version
  version=$(curl -s https://api.github.com/repos/x-motemen/ghq/releases/latest | grep '"tag_name":' | sed -E 's/.*"v([^"]+)".*/\1/')

  if [[ -z "$version" ]]; then
    log_error "Failed to get latest version"
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
  cd "$temp_dir"

  curl -L -o ghq.zip "$download_url"
  unzip ghq.zip

  # ~/.local/bin にインストール
  mkdir -p "$HOME/.local/bin"
  mv ghq*/ghq "$HOME/.local/bin/"
  chmod +x "$HOME/.local/bin/ghq"

  cd - > /dev/null
  rm -rf "$temp_dir"

  log_info "ghq が正常にインストールされました"
}

# mkwork のインストール
install_mkwork() {
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
    if [[ -f "$example_file" ]]; then
      cp "$example_file" "$gitconfig_local"
      log_warn "非対話モード: .gitconfig.local.example をコピーしました"
      log_warn "後で手動で編集してください: $gitconfig_local"
    else
      log_warn "非対話モード: .gitconfig.local.example が見つかりません"
      log_warn "chezmoi apply 後に .gitconfig.local を手動で設定してください"
    fi
  fi
}

# .env のセットアップ
setup_env() {
  log_info ".env をセットアップしています..."

  local env_file="$HOME/.env"
  local example_file="$HOME/.env.example"

  if [[ -f "$env_file" ]]; then
    log_warn ".env が既に存在します (スキップ)"
  else
    # chezmoi apply 後に .env.example が存在する場合はコピー
    # インストール時点では存在しないため、後でコピーするようにメッセージを表示
    log_info ".env は chezmoi apply 後に .env.example からコピーしてください"
  fi
}

# chezmoi apply を実行
apply_chezmoi() {
  log_info "chezmoi の設定を適用しています..."
  chezmoi apply
  log_info "chezmoi の設定が正常に適用されました"

  # .env のコピー
  local env_file="$HOME/.env"
  local example_file="$HOME/.env.example"

  if [[ ! -f "$env_file" ]] && [[ -f "$example_file" ]]; then
    cp "$example_file" "$env_file"
    log_info ".env を .env.example からコピーしました"
    log_warn "Discord Webhook URL などを設定してください: $env_file"
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
