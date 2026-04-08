#!/bin/bash
# Claude Code ステータスライン表示スクリプト
# コンテキストウィンドウの使用状況をカラープログレスバーで表示する

# stdin から JSON を読み込む
INPUT=$(cat)

# コンテキストウィンドウの使用率を取得する（事前計算済みフィールドを優先）
USED_PCT=$(echo "$INPUT" | jq -r '.context_window.used_percentage // empty')

# used_percentage が存在しない場合は percent_used にフォールバックする
if [ -z "$USED_PCT" ]; then
  USED_PCT=$(echo "$INPUT" | jq -r '.context_window.percent_used // empty')
fi

# 使用率が取得できない場合は何も表示せず終了する
if [ -z "$USED_PCT" ]; then
  exit 0
fi

# 使用率を整数に丸める
USED_INT=$(printf "%.0f" "$USED_PCT")

# 使用中のトークン数を取得する
TOKENS_USED=$(echo "$INPUT" | jq -r '.context_window.tokens_used // 0')

# コンテキストウィンドウの最大サイズを取得する
CTX_MAX=$(echo "$INPUT" | jq -r '.context_window.context_window_size // .context_window.current_model_max // 0')

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
# 使用率が 100% を超えた場合はバー幅を上限にクランプする
if [ "$FILLED" -gt "$BAR_WIDTH" ]; then FILLED=$BAR_WIDTH; fi
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
  if [ "$n" -ge 1000 ]; then
    awk "BEGIN { printf \"%.1fK\", $n / 1000 }"
  else
    printf "%d" "$n"
  fi
}

TOKENS_USED_FMT=$(format_tokens "$TOKENS_USED")
CTX_MAX_FMT=$(format_tokens "$CTX_MAX")

# ステータスラインを出力する
printf "${BAR_COLOR}[${BAR_FILLED}${COLOR_DIM}${BAR_EMPTY}${COLOR_RESET}${BAR_COLOR}]${COLOR_RESET} ${BAR_COLOR}${USED_INT}%%${COLOR_RESET} ${COLOR_DIM}(${TOKENS_USED_FMT}/${CTX_MAX_FMT})${COLOR_RESET}"
