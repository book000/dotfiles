#!/bin/bash

# completion-notify スクリプト群で共有する共通ライブラリ

# Windows パスをシェル互換パスに変換する関数
# WSL: C:\Users\... → /mnt/c/Users/...
# Git Bash/MSYS2: C:\Users\... → /c/Users/...
# Linux/Unix: そのまま
convert_path() {
  local path="$1"

  # チルダを HOME に展開
  if [[ "$path" == "~"* ]]; then
    path="${HOME}${path:1}"
  fi

  # Windows パス形式かどうかをチェック (例: C:\ or C:/)
  # 正規表現でバックスラッシュを正しくマッチさせるため、^[A-Za-z]: のみでチェック
  if [[ "$path" =~ ^[A-Za-z]: ]]; then
    local third_char="${path:2:1}"
    # 3 文字目がスラッシュまたはバックスラッシュの場合のみ変換
    if [[ "$third_char" == "/" ]] || [[ "$third_char" == "\\" ]]; then
      local drive_letter="${path:0:1}"
      local rest="${path:2}"
      # バックスラッシュをスラッシュに変換 (tr を使用)
      # shellcheck disable=SC1003
      rest=$(printf '%s' "$rest" | tr '\\' '/')
      # ドライブレターを小文字に変換
      drive_letter=$(printf '%s' "$drive_letter" | tr '[:upper:]' '[:lower:]')

      # 環境を検出してパスを変換
      if [[ -f /proc/version ]] && grep -qiE '(microsoft|wsl)' /proc/version 2>/dev/null; then
        # WSL 環境
        path="/mnt/${drive_letter}${rest}"
      elif [[ -n "$MSYSTEM" ]] || [[ "$(uname -s)" == MINGW* ]] || [[ "$(uname -s)" == MSYS* ]]; then
        # Git Bash/MSYS2 環境
        path="/${drive_letter}${rest}"
      fi
    fi
  fi

  printf '%s\n' "$path"
}
