#!/bin/bash
# chezmoi の自動更新スクリプト
# 24 時間以内に実行済みの場合はスキップする

set -euo pipefail

CACHE_DIR="$HOME/.cache/chezmoi-update"
TIMESTAMP_FILE="$CACHE_DIR/last-update"
CHEZMOI_BIN="$HOME/.local/bin/chezmoi"
MISE_BIN="$HOME/.local/bin/mise"
MISE_GLOBAL_CONFIG_FILE="$HOME/.config/mise/config.toml"
LEGACY_CHEZMOI_BIN="$HOME/bin/chezmoi"
DRIFT_BACKUP_DIR="$CACHE_DIR/drift-backups"
FORCE_UPDATE=0

if [[ $# -gt 0 ]]; then
  if [[ "$1" == "--force" ]]; then
    FORCE_UPDATE=1
    shift
  else
    echo "Unknown option: $1" >&2
    exit 2
  fi
fi
if [[ $# -gt 0 ]]; then
  echo "Unexpected argument: $1" >&2
  exit 2
fi

mkdir -p "$CACHE_DIR"

# AI CLI 起動時更新と systemd timer が重なっても source state を同時更新しない。
exec 9>"$CACHE_DIR/update.lock"
if ! flock -n 9; then
  exit 0
fi

if [[ $FORCE_UPDATE -eq 0 && -f "$TIMESTAMP_FILE" ]]; then
  last_update=$(cat "$TIMESTAMP_FILE" 2>/dev/null || echo "")
  # 非数値・空の場合は 0 扱いにして算術展開エラーを防ぐ
  [[ "$last_update" =~ ^[0-9]+$ ]] || last_update=0
  elapsed=$(( $(date +%s) - last_update ))
  if [[ $elapsed -lt 86400 ]]; then
    exit 0
  fi
fi

backup_modified_targets() {
  local status_output status_line status_code target relative_path backup_path backup_root="" backup_count=0

  status_output=$("$CHEZMOI_BIN" status --path-style=absolute --color=false)
  while IFS= read -r status_line; do
    [[ -n "$status_line" ]] || continue
    status_code="${status_line:0:1}"
    [[ "$status_code" != " " ]] || continue
    [[ "${status_line:2:1}" == " " ]] || {
      echo "Invalid chezmoi status output; refusing to apply changes." >&2
      return 1
    }

    target="${status_line:3}"
    [[ -n "$target" ]] || {
      echo "Invalid chezmoi status output; refusing to apply changes." >&2
      return 1
    }
    case "$target" in
      "$HOME"/*) ;;
      *)
        echo "chezmoi reported a modified target outside HOME; refusing to apply changes." >&2
        return 1
        ;;
    esac

    if [[ ! -e "$target" && ! -L "$target" ]]; then
      if [[ "$status_code" == "D" ]]; then
        continue
      fi
      echo "A modified chezmoi target disappeared before backup; refusing to apply changes." >&2
      return 1
    fi

    if [[ -z "$backup_root" ]]; then
      mkdir -p -- "$DRIFT_BACKUP_DIR"
      if [[ -L "$DRIFT_BACKUP_DIR" || ! -O "$DRIFT_BACKUP_DIR" ]]; then
        echo "The chezmoi drift backup directory is not a private directory owned by the current user." >&2
        return 1
      fi
      chmod 700 -- "$DRIFT_BACKUP_DIR"
      backup_root=$(umask 077; mktemp -d "$DRIFT_BACKUP_DIR/$(date -u +%Y%m%dT%H%M%SZ).XXXXXX")
      chmod 700 -- "$backup_root"
    fi

    relative_path="${target#"$HOME"/}"
    case "$relative_path" in
      ""|.|..|/*|./*|../*|*/./*|*/../*|*/.|*/..)
        echo "chezmoi reported an unsafe target path; refusing to apply changes." >&2
        return 1
        ;;
    esac

    backup_path="$backup_root/$relative_path"
    mkdir -p -- "$(dirname -- "$backup_path")"
    cp -a -- "$target" "$backup_path"
    backup_count=$((backup_count + 1))
  done <<< "$status_output"

  if [[ $backup_count -gt 0 ]]; then
    echo "Backed up $backup_count locally modified chezmoi target(s) before non-interactive apply."
  fi
}

update_chezmoi() {
  if [[ -t 0 && -t 1 ]]; then
    "$CHEZMOI_BIN" update
    return
  fi

  "$CHEZMOI_BIN" update --apply=false
  backup_modified_targets
  "$CHEZMOI_BIN" apply --force
}

# chezmoi の公式インストーラで ~/.local/bin の単一バイナリを更新する。
installer=$(curl -fsSL --retry 5 --retry-delay 5 https://get.chezmoi.io)
sh -c "$installer" -- -b "$HOME/.local/bin"

# インストーラ経由の暗黙実行に依存せず、管理対象のバイナリを明示して更新する。
update_chezmoi

# chezmoi で反映された global config に宣言済みの tool を揃える。
MISE_GLOBAL_CONFIG_FILE="$MISE_GLOBAL_CONFIG_FILE" "$MISE_BIN" install

# 旧 updater が作成した ~/bin/chezmoi は、正常更新後に削除して二重管理を解消する。
rm -f -- "$LEGACY_CHEZMOI_BIN"

date +%s > "$TIMESTAMP_FILE"
