# SSHログイン時（tmux外・TTYあり）に tmux セッション選択UI（fzf）を起動する。
#
# 設計ポイント（重要）:
# - セッション名が「0」「1」のような数字でも誤解釈されないよう、tmux ターゲットは常に "${session_name}:" で厳密指定する
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
        # shellcheck source=/dev/null
        [[ -f "$f" ]] && source "$f"
      done
    fi
  }

  _tmux_collect_extra_actions() {
    # fzf 入力（4 カラム）:
    # DISPLAY<TAB>TYPE<TAB>KEY<TAB>PANE_ID
    # ACTION は PANE_ID を空にする
    if declare -F tmux_extra_actions >/dev/null 2>&1; then
      tmux_extra_actions 2>/dev/null | while IFS=$'\t' read -r action_id label cmd; do
        [[ -n "$action_id" && -n "$label" && -n "$cmd" ]] || continue
        # タブ文字が含まれると TSV の区切りが崩れるため、スペースに置換する
        local safe_label="${label//$'\t'/ }"
        printf "%s\tACTION\t%s\t\n" "$safe_label" "$action_id"
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

  # fzf 入力（タブ区切り 4 カラム）: DISPLAY<TAB>TYPE<TAB>KEY<TAB>PANE_ID
  # DISPLAY を先頭カラムにすることで --with-nth=1 を使え、fzf の古いバージョンでの
  # フィールド番号の曖昧さ（--with-nth=3 の誤動作）を回避できる
  local detailed_options=""
  if [[ -n "$sessions" ]]; then
    local sname sattached swindows screated
    local attach_status pane_id cwd cmd display

    while IFS='|' read -r sname sattached swindows screated; do
      [[ -n "$sname" ]] || continue

      # 経過時間を短縮形で算出（例: 5s, 3m, 2h, 1d）
      # 行末ではなくコマンドの直後に配置することでモバイル幅でも見切れを防ぐ
      local now_ts age_str
      now_ts="$(date +%s 2>/dev/null || echo 0)"
      if [[ -n "$screated" && "$screated" != "0" && "$now_ts" -gt 0 ]]; then
        local diff=$(( now_ts - screated ))
        if   (( diff < 60     )); then age_str="${diff}s"
        elif (( diff < 3600   )); then age_str="$(( diff / 60 ))m"
        elif (( diff < 86400  )); then age_str="$(( diff / 3600 ))h"
        else                           age_str="$(( diff / 86400 ))d"
        fi
      else
        age_str="?"
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

        # TMUX_PROJECT_DIR が設定されていれば優先する。
        # pane_current_path はサブプロセスの影響で一時的に別ディレクトリを指すことがあるため信頼性が低い。
        # 設定方法: tmux new-session -e TMUX_PROJECT_DIR="$(pwd)"
        #           または tmux set-environment -t <session> TMUX_PROJECT_DIR "$(pwd)"
        local project_dir
        project_dir="$(tmux show-environment -t "${sname}" TMUX_PROJECT_DIR 2>/dev/null)"
        if [[ "$project_dir" == TMUX_PROJECT_DIR=* ]]; then
          cwd="${project_dir#TMUX_PROJECT_DIR=}"
        else
          cwd="$(tmux display-message -p -t "$pane_id" '#{pane_current_path}' 2>/dev/null || echo "?")"
        fi
        [[ -n "${HOME:-}" ]] && cwd="${cwd/#$HOME/\~}"
        if [[ "${#cwd}" -gt "$TMUX_PATH_MAX" ]]; then
          cwd="…${cwd: -$TMUX_PATH_MAX}"
        fi
      fi

      # フォーマット: "NAME: [CMD|AGE] (PATH) Nw [(attached)]"
      # AGE をコマンドの直後に入れることで、パスが長くても作成時期が見切れない
      display="$sname: [$cmd|$age_str] ($cwd) ${swindows}w$attach_status"
      # タブ文字が含まれると TSV の区切りが崩れるため、スペースに置換する
      display="${display//$'\t'/ }"
      # KEY は session_name。tmux のターゲット指定は "${session_name}:" で厳密に扱う
      # フィールド順: DISPLAY<TAB>TYPE<TAB>KEY<TAB>PANE_ID
      detailed_options+="$display"$'\t'"SESSION"$'\t'"$sname"$'\t'"$pane_id"$'\n'
    done <<< "$sessions"
  fi

  # セッション0件でも必ず NEW を出す（即 new-session はしない）
  # フィールド順: DISPLAY<TAB>TYPE<TAB>KEY<TAB>PANE_ID（PANE_IDは空）
  detailed_options+="Create New Session: [new] Create a new tmux session"$'\t'"NEW"$'\t'"__new__"$'\t'

  # ACTION（任意）
  local extra_actions
  extra_actions="$(_tmux_collect_extra_actions)"
  if [[ -n "$extra_actions" ]]; then
    detailed_options+=$'\n'"$extra_actions"
  fi

  # --- fzf preview ---
  # クォート崩壊を避けるため、bash -c に {2}{3}{4} を引数で渡す
  local preview_cmd
  # shellcheck disable=SC2016
  # フィールド順: DISPLAY{1}<TAB>TYPE{2}<TAB>KEY{3}<TAB>PANE_ID{4}
  # bash -c の引数: _ TYPE KEY PANE_ID（DISPLAYはプレビューに不要のためスキップ）
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
  '\'' _ {2} {3} {4}'

  # --- fzf ---
  # --no-sort を付けない理由: --filter モードでは --no-sort + --with-nth の組み合わせで
  # フィールドが剥ぎ取られる挙動が fzf 0.29 系で確認されているため、副作用を避けて外している。
  # インタラクティブモードでは --no-sort の有無に関わらず選択結果は全フィールドを含む。
  # クエリ未入力時は全アイテムのスコアが 0 で安定ソートされ入力順が保たれる。
  local selected
  if [[ "$terminal_width" -ge "$TMUX_MIN_WIDTH" ]]; then
    selected="$(
      printf "%s\n" "$detailed_options" | fzf \
        --height="$TMUX_FZF_HEIGHT" \
        --reverse \
        --border \
        --delimiter=$'\t' \
        --with-nth=1 \
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
        --with-nth=1 \
        --prompt='Select session/action: '
    )" || return 1
  fi

  [[ -z "$selected" ]] && return 1

  # フィールド順: DISPLAY{1}<TAB>TYPE{2}<TAB>KEY{3}<TAB>PANE_ID{4}
  local sel_type sel_key
  sel_type="$(printf "%s" "$selected" | cut -f2)"
  sel_key="$(printf "%s" "$selected" | cut -f3)"

  case "$sel_type" in
    NEW)
      sleep "$TMUX_SESSION_DELAY"
      # TMUX_PROJECT_DIR を現在のディレクトリで設定してセッションを作成する。
      # 以降はセレクタが pane_current_path の代わりにこの値を使うため表示が安定する。
      tmux new-session -e "TMUX_PROJECT_DIR=$(pwd)"
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
