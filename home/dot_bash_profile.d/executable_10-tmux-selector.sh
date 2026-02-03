# SSHログイン時（tmux外・TTYあり）に tmux セッション選択UI（fzf）を起動する。
#
# 設計ポイント（重要）:
# - セッション名が「0」「1」のような数字でも誤解釈されないよう、tmuxターゲットは常に "${session_name}:" で厳密指定する
#   （tmux 3.2a では "=1" が window 1 と誤解釈されるバグがあるため、session_name: 構文を使用）
# - セッション0件でも即 new-session しない（必ず選択UIを出す）
# - 候補にはアクティブpaneの cwd を表示
# - プレビューは pane_id を使う（セッション名を直接使わない）
# - プレビュー失敗時は理由を必ず表示（「更新されない」を可視化）
# - 拡張: ~/.tmux_session_selector.d/*.sh で ACTION 追加（任意）
#     各 *.sh は tmux_extra_actions 関数を定義できる
#     出力形式: ACTION_ID<TAB>LABEL<TAB>COMMAND

tmux_session_selector() {
  # --- Config (override via env) ---
  TMUX_PREVIEW_LINES=${TMUX_PREVIEW_LINES:-50}     # プレビュー末尾N行
  TMUX_FZF_HEIGHT=${TMUX_FZF_HEIGHT:-60}           # fzf 高さ
  TMUX_PREVIEW_HEIGHT=${TMUX_PREVIEW_HEIGHT:-80%}  # プレビュー領域高さ（up:）
  TMUX_SESSION_DELAY=${TMUX_SESSION_DELAY:-1}      # NEW選択後の待ち（秒）
  TMUX_MIN_WIDTH=${TMUX_MIN_WIDTH:-80}             # プレビュー有効化の最小幅（cols）
  TMUX_PATH_MAX=${TMUX_PATH_MAX:-60}               # cwd 表示の最大長（文字数）

  export TMUX_FZF_PREVIEW_LINES="$TMUX_PREVIEW_LINES"

  # --- Dependency checks ---
  command -v tmux >/dev/null 2>&1 || { echo "tmux not found in PATH." >&2; return 1; }
  command -v fzf  >/dev/null 2>&1 || { echo "fzf not found in PATH."  >&2; return 1; }
  command -v tput >/dev/null 2>&1 || { echo "tput not found in PATH." >&2; return 1; }

  local terminal_width
  terminal_width="$(tput cols 2>/dev/null || echo 80)"

  # --- Extensibility: load extra action providers ---
  _tmux_load_action_providers() {
    local d="${HOME}/.tmux_session_selector.d"
    if [[ -d "$d" ]]; then
      local f
      for f in "$d"/*.sh; do
        [[ -f "$f" ]] && # shellcheck source=/dev/null
          source "$f"
      done
    fi
  }

  _tmux_collect_extra_actions() {
    # fzf入力（4カラム）:
    # TYPE<TAB>KEY<TAB>DISPLAY<TAB>PREVIEW_TARGET
    # ACTION は PREVIEW_TARGET を空にする
    if declare -F tmux_extra_actions >/dev/null 2>&1; then
      tmux_extra_actions 2>/dev/null | while IFS=$'\t' read -r action_id label cmd; do
        [[ -n "$action_id" && -n "$label" && -n "$cmd" ]] || continue
        printf "ACTION\t%s\t%s\t\n" "$action_id" "$label"
      done
    fi
  }

  _tmux_run_action() {
    local action_id="$1"
    if ! declare -F tmux_extra_actions >/dev/null 2>&1; then
      echo "No action providers loaded." >&2
      return 1
    fi

    local cmd=""
    cmd="$(tmux_extra_actions 2>/dev/null | awk -F'\t' -v id="$action_id" '$1==id {print $3; exit}')" || true
    if [[ -z "$cmd" ]]; then
      echo "Action not found: $action_id" >&2
      return 1
    fi

    # 現在のシェル文脈（PWD含む）で実行
    eval "$cmd"
  }

  _tmux_load_action_providers

  # --- Sessions list (tmux server may not be running) ---
  # \t は環境によって文字列として出ることがあるため、区切りは '|' を使用
  local sessions
  sessions="$(tmux list-sessions -F '#{session_name}|#{session_attached}|#{session_windows}|#{session_created}' 2>/dev/null || true)"

  # fzf入力（タブ区切り 4カラム）
  local detailed_options=""
  if [[ -n "$sessions" ]]; then
    local sname sattached swindows screated
    local created_fmt attach_status pane_id cwd cmd display

    while IFS='|' read -r sname sattached swindows screated; do
      [[ -n "$sname" ]] || continue

      # created整形（GNU date / BSD date fallback）
      if [[ -n "$screated" && "$screated" != "0" ]]; then
        created_fmt="$(
          date -d "@$screated" "+%Y/%m/%d %H:%M:%S" 2>/dev/null \
          || date -r "$screated" "+%Y/%m/%d %H:%M:%S" 2>/dev/null \
          || echo "$screated"
        )"
      else
        created_fmt="unknown"
      fi

      [[ "${sattached:-0}" -gt 0 ]] && attach_status=" (attached)" || attach_status=""

      # 重要: 数字名でも壊れないよう "${session_name}:" で厳密指定
      pane_id="$(tmux list-panes -t "${sname}:" -F '#{pane_id} #{pane_active}' 2>/dev/null | awk '$2==1{print $1;exit}')"
      if [[ -z "$pane_id" ]]; then
        pane_id="$(tmux list-panes -t "${sname}:" -F '#{pane_id}' 2>/dev/null | head -n1)"
      fi

      cmd="unknown"
      cwd="?"
      if [[ -n "$pane_id" ]]; then
        cmd="$(tmux display-message -p -t "$pane_id" '#{pane_current_command}' 2>/dev/null || echo "unknown")"
        cwd="$(tmux display-message -p -t "$pane_id" '#{pane_current_path}' 2>/dev/null || echo "?")"
        [[ -n "${HOME:-}" ]] && cwd="${cwd/#$HOME/\~}"
        if [[ "${#cwd}" -gt "$TMUX_PATH_MAX" ]]; then
          cwd="…${cwd: -$TMUX_PATH_MAX}"
        fi
      fi

      display="$sname: [$cmd] ($cwd) ${swindows}w (created $created_fmt)$attach_status"
      # KEY は session_name（ただし attach は必ず =name を使う）
      detailed_options+="SESSION"$'\t'"$sname"$'\t'"$display"$'\t'"$pane_id"$'\n'
    done <<< "$sessions"
  fi

  # セッション0件でも必ず NEW を出す（即 new-session はしない）
  detailed_options+="NEW"$'\t'"__new__"$'\t'"Create New Session: [new] Create a new tmux session"$'\t'

  # ACTION（任意）
  local extra_actions
  extra_actions="$(_tmux_collect_extra_actions)"
  if [[ -n "$extra_actions" ]]; then
    detailed_options+=$'\n'"$extra_actions"
  fi

  # --- fzf preview ---
  # クォート崩壊を避けるため、bash -c に {1}{2}{4} を引数で渡す
  local preview_cmd
  preview_cmd='bash -c '\''
  t="$1"; key="$2"; pane="$3";
  lines="${TMUX_FZF_PREVIEW_LINES:-15}"

  if [[ "$t" == "SESSION" ]]; then
    if [[ -z "$pane" ]]; then
      echo "preview: no pane_id (session=$key)"
      exit 0
    fi
    if ! out="$(tmux capture-pane -p -t "$pane" -S -"${lines}" 2>&1)"; then
      echo "preview: tmux capture-pane failed"
      echo "session=$key pane=$pane"
      echo "$out"
      exit 0
    fi
    printf "%s\n" "$out" | sed -E "s/\x1B\[[0-9;]*[[:alpha:]]//g"
  elif [[ "$t" == "NEW" ]]; then
    echo "Will create a new tmux session"
  elif [[ "$t" == "ACTION" ]]; then
    echo "Will run action: $key"
  else
    echo "preview: unknown type=$t"
  fi
  '\'' _ {1} {2} {4}'

  # --- fzf ---
  local selected
  if [[ "$terminal_width" -ge "$TMUX_MIN_WIDTH" ]]; then
    selected="$(
      printf "%s\n" "$detailed_options" | fzf \
        --height="$TMUX_FZF_HEIGHT" \
        --reverse \
        --border \
        --delimiter=$'\t' \
        --with-nth=3 \
        --prompt='Select session/action: ' \
        --preview-window=up:"$TMUX_PREVIEW_HEIGHT":follow:wrap \
        --preview "$preview_cmd"
    )" || return 1
  else
    echo "Terminal width: ${terminal_width} (min: ${TMUX_MIN_WIDTH}) - Preview disabled" >&2
    selected="$(
      printf "%s\n" "$detailed_options" | fzf \
        --height="$TMUX_FZF_HEIGHT" \
        --reverse \
        --border \
        --delimiter=$'\t' \
        --with-nth=3 \
        --prompt='Select session/action: '
    )" || return 1
  fi

  [[ -z "$selected" ]] && return 1

  local sel_type sel_key
  sel_type="$(printf "%s" "$selected" | cut -f1)"
  sel_key="$(printf "%s" "$selected" | cut -f2)"

  case "$sel_type" in
    NEW)
      sleep "$TMUX_SESSION_DELAY"
      tmux new-session
      ;;
    SESSION)
      # 重要: 数字名でも曖昧にならないよう session_name: で attach
      tmux attach-session -t "${sel_key}:"
      ;;
    ACTION)
      _tmux_run_action "$sel_key"
      ;;
    *)
      echo "Unknown selection type: $sel_type" >&2
      return 1
      ;;
  esac
}

# SSH接続かつtmux外かつTTYありのときのみ自動起動（scp/rsync等を避ける）
if [[ -z "${TMUX:-}" && -n "${SSH_CONNECTION:-}" && -t 0 && -t 1 && $- == *i* && -z "${TMUX_SELECTOR_DISABLE_AUTO:-}" ]]; then
  while true; do
    sleep 1
    tmux_session_selector || break
  done
fi
