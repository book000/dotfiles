#!/bin/bash
# AI エージェント CLI ツールの自動更新スクリプト
#
# 対象ツール:
# - Claude Code (native install)
# - GitHub Copilot CLI
# - OpenAI Codex CLI (npm)
# - Chrome MCP Router / Chrome DevTools MCP (npm)

set -euo pipefail

# ログとキャッシュディレクトリ
CACHE_DIR="$HOME/.cache/update-ai-agents"
TIMESTAMP_FILE="$CACHE_DIR/last-update"
LOG_FILE="$CACHE_DIR/update.log"
LOCK_FILE="$CACHE_DIR/update.lock"

mkdir -p "$CACHE_DIR"

# ロギング関数
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

# ログローテーション (10 MB 超えたらローテーション)
rotate_log() {
    if [[ -f "$LOG_FILE" ]] && [[ $(stat -c%s "$LOG_FILE" 2>/dev/null || echo 0) -gt 10485760 ]]; then
        mv "$LOG_FILE" "$LOG_FILE.old"
        gzip "$LOG_FILE.old" 2>/dev/null || true
    fi
}

# ロックファイル機構
acquire_lock() {
    # 古いロックファイルのクリーンアップ (1 時間以上前)
    if [[ -f "$LOCK_FILE" ]]; then
        local lock_age=$(($(date +%s) - $(stat -c %Y "$LOCK_FILE" 2>/dev/null || echo 0)))
        if [[ $lock_age -gt 3600 ]]; then
            rm -f "$LOCK_FILE"
        else
            log "⚠️  Another update is running (lock age: $((lock_age / 60)) minutes)"
            exit 0
        fi
    fi

    trap 'rm -f "$LOCK_FILE"' EXIT
    touch "$LOCK_FILE"
}

# タイムスタンプチェック (--quick オプション用)
check_timestamp() {
    if [[ -f "$TIMESTAMP_FILE" ]]; then
        local last_update
        last_update=$(cat "$TIMESTAMP_FILE" 2>/dev/null || echo 0)
        local current_time
        current_time=$(date +%s)
        local elapsed=$((current_time - last_update))

        # 24 時間以内ならスキップ
        if [[ $elapsed -lt 86400 ]]; then
            log "⏭️  Skipping update (last update: $((elapsed / 3600)) hours ago)"
            exit 0
        fi
    fi
}

# ネットワーク接続チェック
check_network() {
    # curl コマンドの存在確認
    if ! command -v curl >/dev/null 2>&1; then
        log "⚠️  curl not found, skipping network check"
        return 0  # curl がない場合は更新を続行
    fi

    # 複数のエンドポイントを試行
    local targets=(
        "https://www.google.com"
        "https://1.1.1.1"
    )

    for target in "${targets[@]}"; do
        if curl -s --connect-timeout 3 --max-time 5 "$target" >/dev/null 2>&1; then
            # いずれか 1 つが成功すれば OK
            return 0
        fi
    done

    # すべて失敗した場合
    log "⚠️  No network connection, skipping update"
    exit 0
}

# ディスク容量チェック
check_disk_space() {
    local available
    available=$(df -BM "$CACHE_DIR" 2>/dev/null | awk 'NR==2 {print $4}' | tr -d 'M' || echo 1000)
    if [[ $available -lt 100 ]]; then
        log "❌ Insufficient disk space: ${available} MB available"
        exit 1
    fi
}

# npm 権限チェック
check_npm_permissions() {
    if ! command -v npm >/dev/null 2>&1; then
        return 0  # npm がない場合はスキップ
    fi

    local npm_prefix
    npm_prefix=$(npm config get prefix 2>/dev/null || echo "$HOME/.local")

    if [[ ! -w "$npm_prefix" ]]; then
        log "⚠️  No write permission to npm prefix: $npm_prefix"
        log "💡 Consider: npm config set prefix ~/.local"
        return 1
    fi
}

# プロセス実行中チェック (pidof 優先)
is_running() {
    local cmd=$1
    pidof "$cmd" >/dev/null 2>&1
}

# Claude Code の更新
update_claude() {
    if ! command -v claude >/dev/null 2>&1; then
        log "⏭️  Claude Code not installed, skipping"
        return 0
    fi

    if is_running claude; then
        log "⏭️  Claude Code is running, skipping update"
        return 0
    fi

    log "🔄 Updating Claude Code..."
    # Native install は自動更新が有効なため、手動更新は必須ではない
    # エラーが発生しても続行
    if claude update 2>&1 | tee -a "$LOG_FILE"; then
        log "✅ Claude Code update completed"
    else
        log "⚠️  Claude Code update failed or not needed (exit code: $?)"
    fi
}

# Copilot CLI の更新
update_copilot() {
    if ! command -v copilot >/dev/null 2>&1; then
        log "⏭️  Copilot CLI not installed, skipping"
        return 0
    fi

    if is_running copilot; then
        log "⏭️  Copilot CLI is running, skipping update"
        return 0
    fi

    log "🔄 Updating GitHub Copilot CLI..."

    # 優先: copilot update コマンド
    if copilot update --help &>/dev/null; then
        if copilot update 2>&1 | tee -a "$LOG_FILE"; then
            log "✅ Copilot CLI updated successfully"
            return 0
        fi
    fi

    # フォールバック: npm
    if command -v npm >/dev/null 2>&1; then
        log "⚠️  Trying npm update as fallback..."
        if npm install -g @github/copilot@latest 2>&1 | tee -a "$LOG_FILE"; then
            log "✅ Copilot CLI updated via npm"
            return 0
        fi
    fi

    log "❌ Copilot CLI update failed"
    return 1
}

# Codex CLI の更新
update_codex() {
    if ! command -v codex >/dev/null 2>&1; then
        log "⏭️  Codex CLI not installed, skipping"
        return 0
    fi

    if is_running codex; then
        log "⏭️  Codex CLI is running, skipping update"
        return 0
    fi

    if ! command -v npm >/dev/null 2>&1; then
        log "⚠️  npm not found, skipping Codex CLI update"
        return 1
    fi

    log "🔄 Updating Codex CLI..."
    if npm install -g @openai/codex@latest 2>&1 | tee -a "$LOG_FILE"; then
        log "✅ Codex CLI updated successfully"
    else
        log "❌ Codex CLI update failed"
        return 1
    fi
}

# 新しい release の MCP initialize を確認する。
smoke_test_chrome_mcp() {
    local release_dir="$1"
    local browser_url="${CHROME_MCP_BROWSER_URL:-http://127.0.0.1:9222}"
    local project="${CHROME_MCP_PROJECT:-}"
    local timeout_seconds="${CHROME_MCP_SMOKE_TIMEOUT_SECONDS:-10}"
    local router="$release_dir/node_modules/.bin/chrome-mcp-router"
    local helper="${CHROME_MCP_SMOKE_HELPER:-$HOME/bin/chrome-mcp-smoke-test.mjs}"

    if [[ ! -x "$router" ]]; then
        log "❌ Chrome MCP Router executable was not installed"
        return 1
    fi

    if ! [[ "$timeout_seconds" =~ ^[1-9][0-9]*$ ]]; then
        log "❌ CHROME_MCP_SMOKE_TIMEOUT_SECONDS must be a positive integer"
        return 1
    fi
    if [[ ! -f "$helper" ]]; then
        log "❌ Chrome MCP smoke test helper was not installed"
        return 1
    fi

    if [[ -n "$project" ]]; then
        log "🔍 Running Chrome MCP initialize smoke test for project ${project}..."
        if ! node "$helper" --router "$router" --project "$project" --timeout-seconds "$timeout_seconds"; then
            log "❌ Chrome MCP initialize smoke test failed"
            return 1
        fi
    else
        log "🔍 Running Chrome MCP initialize smoke test against ${browser_url}..."
        if ! node "$helper" --router "$router" --browser-url "$browser_url" --timeout-seconds "$timeout_seconds"; then
            log "❌ Chrome MCP initialize smoke test failed"
            return 1
        fi
    fi

    log "✅ Chrome MCP initialize smoke test passed"
}

# chrome-mcp-router と chrome-devtools-mcp を同一 release として更新する。
update_chrome_mcp_router() {
    if ! command -v npm >/dev/null 2>&1; then
        log "⚠️  npm not found, skipping Chrome MCP update"
        return 1
    fi
    if ! command -v node >/dev/null 2>&1; then
        log "⚠️  node not found, skipping Chrome MCP update"
        return 1
    fi

    local install_dir="${CHROME_MCP_INSTALL_DIR:-$HOME/.local/share/chrome-mcp-router}"
    local releases_dir="$install_dir/releases"
    local staging_dir
    local router_version
    local devtools_version
    local release_name
    local release_dir
    local switch_link

    mkdir -p "$releases_dir"
    staging_dir=$(mktemp -d "$releases_dir/.staging.XXXXXX")

    log "🔄 Updating Chrome MCP packages in staging..."
    if ! npm install --prefix "$staging_dir" --no-audit --no-fund chrome-mcp-router@latest chrome-devtools-mcp@latest 2>&1 | tee -a "$LOG_FILE"; then
        rm -rf "$staging_dir"
        log "❌ Chrome MCP package installation failed"
        return 1
    fi

    if ! smoke_test_chrome_mcp "$staging_dir"; then
        rm -rf "$staging_dir"
        return 1
    fi

    router_version=$(node -p 'require(process.argv[1]).version' "$staging_dir/node_modules/chrome-mcp-router/package.json")
    devtools_version=$(node -p 'require(process.argv[1]).version' "$staging_dir/node_modules/chrome-devtools-mcp/package.json")
    release_name="router-${router_version//[^A-Za-z0-9._-]/_}__devtools-${devtools_version//[^A-Za-z0-9._-]/_}"
    release_dir="$releases_dir/$release_name"

    if [[ -e "$release_dir" && ! -d "$release_dir" ]]; then
        rm -rf "$staging_dir"
        log "❌ Chrome MCP release path is not a directory: $release_dir"
        return 1
    fi
    if [[ -d "$release_dir" ]]; then
        rm -rf "$staging_dir"
    else
        mv "$staging_dir" "$release_dir"
    fi

    switch_link="$install_dir/.current.$$"
    ln -s "releases/$release_name" "$switch_link"
    mv -Tf "$switch_link" "$install_dir/current"
    log "✅ Chrome MCP release activated: $release_name"
}

# メイン処理
main() {
    # オプション解析
    local quick=0
    local only_agent=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --quick) quick=1 ;;
            --only)
                if [[ -z "${2:-}" ]]; then
                    echo "❌ --only requires a target name (claude|copilot|codex|chrome-mcp-router)" >&2
                    exit 1
                fi
                case "$2" in
                    claude|copilot|codex|chrome-mcp-router) ;;
                    *)
                        echo "❌ Unknown update target: $2 (claude|copilot|codex|chrome-mcp-router)" >&2
                        exit 1
                        ;;
                esac
                only_agent="$2"
                shift
                ;;
            *) ;;
        esac
        shift
    done

    # エージェントが指定された場合はタイムスタンプ・ロックファイルを個別に設定
    if [[ -n "$only_agent" ]]; then
        TIMESTAMP_FILE="$CACHE_DIR/last-update-${only_agent}"
        LOCK_FILE="$CACHE_DIR/update-${only_agent}.lock"
    fi

    # ログローテーション
    rotate_log

    # --quick オプションの処理
    if [[ $quick -eq 1 ]]; then
        check_timestamp
    fi

    # ロック取得
    acquire_lock

    log "================================================"
    log "🚀 Starting AI agents update check${only_agent:+ (only: ${only_agent})}"
    log "================================================"

    # 環境チェック
    check_network
    check_disk_space
    check_npm_permissions || log "⚠️  npm permission issue detected"

    local exit_code=0

    # 更新対象の選択 (--only 指定時は対象エージェントのみ更新)
    if [[ -n "$only_agent" ]]; then
        case "$only_agent" in
            claude)  update_claude  || exit_code=1 ;;
            copilot) update_copilot || exit_code=1 ;;
            codex)   update_codex   || exit_code=1 ;;
            chrome-mcp-router) update_chrome_mcp_router || exit_code=1 ;;
            *) log "⏭️  No update function for: ${only_agent}" ;;
        esac
    else
        # 各エージェントを個別に更新 (1 つ失敗しても続行)
        update_claude   || exit_code=1
        update_copilot  || exit_code=1
        update_codex    || exit_code=1
    fi

    # タイムスタンプ更新 (成功時のみ)
    if [[ $exit_code -eq 0 ]]; then
        date +%s > "$TIMESTAMP_FILE"
    fi

    log "================================================"
    log "✅ Update check completed (exit code: ${exit_code})"
    log "================================================"

    exit "$exit_code"
}

main "$@"
