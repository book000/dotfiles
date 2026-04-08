#!/bin/bash
# Claude Code ステータスライン表示スクリプト
# コンテキストウィンドウの使用状況をカラープログレスバーで表示する

# stdin から JSON を読み込む
INPUT=$(cat)

# jq を 1 回だけ呼び出して必要なフィールドをまとめて取得する（オーバーヘッド削減）
read -r USED_PCT TOKENS_USED CTX_MAX <<< "$(
  echo "$INPUT" | jq -r '
    [
      (.context_window.used_percentage // .context_window.percent_used // ""),
      (.context_window.tokens_used // 0 | tostring),
      (.context_window.context_window_size // .context_window.current_model_max // 0 | tostring)
    ] | join("\t")
  ' 2>/dev/null
)"

# 使用率が取得できない場合は何も表示せず終了する
if [ -z "$USED_PCT" ]; then
  exit 0
fi

# 使用率を整数に丸める（非数値入力時は 0 にフォールバック）
USED_INT=$(printf "%.0f" "$USED_PCT" 2>/dev/null || printf "0")

# 丸め結果が不正な値の場合は 0 に補正する
case "$USED_INT" in
  ''|*[!0-9-]*)
    USED_INT=0
    ;;
esac

# プログレスバー算出前に 0〜100 にクランプする
if [ "$USED_INT" -lt 0 ]; then
  USED_INT=0
elif [ "$USED_INT" -gt 100 ]; then
  USED_INT=100
fi

# ANSI カラーコードの定義
COLOR_RESET="\033[0m"
COLOR_GREEN="\033[32m"
COLOR_YELLOW="\033[33m"
COLOR_RED="\033[31m"
COLOR_DIM="\033[2m"

# 使用率に応じてバーの色を選択する
if [ "$USED_INT" -lt 50 ]; then
  BAR_COLOR="$COLOR_GREEN"
elif [ "$USED_INT" -le 80 ]; then
  BAR_COLOR="$COLOR_YELLOW"
else
  BAR_COLOR="$COLOR_RED"
fi

# プログレスバーを生成する（合計 20 文字分）
BAR_WIDTH=20
FILLED=$(( USED_INT * BAR_WIDTH / 100 ))
EMPTY=$(( BAR_WIDTH - FILLED ))

BAR_FILLED=""
for ((i = 0; i < FILLED; i++)); do
  BAR_FILLED="${BAR_FILLED}█"
done

BAR_EMPTY=""
for ((i = 0; i < EMPTY; i++)); do
  BAR_EMPTY="${BAR_EMPTY}░"
done

# トークン数を K 単位の文字列に変換する（1000 未満はそのまま整数表示）
format_tokens() {
  local n="$1"
  # 数値以外は 0 として扱う
  case "$n" in
    ''|*[!0-9.]*|*.*.*)
      n=0
      ;;
  esac
  if [ "${n%.*}" -ge 1000 ] 2>/dev/null; then
    # -v で値を渡してシェル展開によるコード注入を防ぐ
    awk -v n="$n" 'BEGIN { printf "%.1fK", n / 1000 }'
  else
    printf "%d" "${n%.*}"
  fi
}

TOKENS_USED_FMT=$(format_tokens "$TOKENS_USED")
CTX_MAX_FMT=$(format_tokens "$CTX_MAX")

# ステータスラインを出力する
printf "${BAR_COLOR}[${BAR_FILLED}${COLOR_DIM}${BAR_EMPTY}${COLOR_RESET}${BAR_COLOR}]${COLOR_RESET} ${BAR_COLOR}${USED_INT}%%${COLOR_RESET} ${COLOR_DIM}(${TOKENS_USED_FMT}/${CTX_MAX_FMT})${COLOR_RESET}"
