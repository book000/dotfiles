# shellcheck shell=bash disable=SC1003,SC2016
# git-config-guard.sh から source される判定ロジック(単独では実行しない)。
# Claude 用 (~/.claude/hooks) と Codex 用 (~/.codex/hooks) に同一内容を置く。
# 一致は tests/unit/test_git_config_guard.sh が cmp で検証する。
#
# 目的: ホストの git 設定への書き込みを、シェルの構文を理解したうえで検出する。
# 文字列 "git config" の部分一致では、heredoc 本文・クォート内のデータ・
# リダイレクトを誤検出し、逆に "git -C dir config" のような形を見逃すため。
#
# 方式: コマンド文字列を字句解析して単純コマンドに分け、コマンド位置(先頭の
# 環境変数代入と command/sudo/env 等の前置を除いた位置)が git で、最初の
# サブコマンドが config のものだけを判定する。bash -c / eval / $(...) / `...` /
# <(...) / stdin を読むシェルへの heredoc・パイプは中身を再帰的に解析する。
#
# 既知の未対応(いずれも静的には中身を特定できない):
# スクリプトファイルの実行(bash x.sh, source)、変数展開で組み立てたコマンド名、
# alias / git alias、python 等の別言語経由、ssh 先、$'\x..' 等のエスケープ復号。

# gcg_heredocs の <<- 判定でタブの繰り返しパターンを使う(定義の解析前に有効化が必要)
shopt -s extglob

GCG_DENY=0
GCG_CONTAINER=host
GCG_STDIN=""
GCG_IDX=0
GCG_MODE=free
GCG_CWD=""

# $1 が書き込み系の git config を含めば 0 を返す。
gcg_denies() {
    local LC_ALL=C
    GCG_DENY=0
    GCG_CONTAINER=host
    GCG_STDIN=""
    GCG_CWD=${2:-}
    gcg_scan "$1" 0
    [[ "$GCG_DENY" -eq 1 ]]
}

# $2 から始まる位置以降で、対応する ")" の位置を GCG_IDX に入れる(なければ末尾)。
gcg_close_paren() {
    local t=$1 i=$2 d=1 n=${#1} c rest pre
    while ((i < n)); do
        c=${t:i:1}
        case $c in
        '\') i=$((i + 1)) ;;
        "'")
            rest=${t:i+1}
            pre=${rest%%\'*}
            i=$((i + ${#pre} + 1))
            ;;
        '"')
            i=$((i + 1))
            while ((i < n)); do
                c=${t:i:1}
                if [[ $c == '\' ]]; then
                    i=$((i + 2))
                    continue
                fi
                [[ $c == '"' ]] && break
                i=$((i + 1))
            done
            ;;
        '(') d=$((d + 1)) ;;
        ')')
            d=$((d - 1))
            if ((d == 0)); then
                GCG_IDX=$i
                return 0
            fi
            ;;
        esac
        i=$((i + 1))
    done
    GCG_IDX=$n
}

# $2 から始まる位置以降で、対応する逆引用符の位置を GCG_IDX に入れる(なければ末尾)。
gcg_close_tick() {
    local t=$1 i=$2 n=${#1} c
    while ((i < n)); do
        c=${t:i:1}
        if [[ $c == '\' ]]; then
            i=$((i + 2))
            continue
        fi
        if [[ $c == '`' ]]; then
            GCG_IDX=$i
            return 0
        fi
        i=$((i + 1))
    done
    GCG_IDX=$n
}

# gcg_scan 内からだけ呼ぶ。s / i / cur / depth は動的スコープで gcg_scan のローカルを参照する。
gcg_take_paren() {
    local e sub
    gcg_close_paren "$s" $((i + 2))
    e=$GCG_IDX
    sub=${s:i+2:e-i-2}
    gcg_scan "$sub" $((depth + 1))
    cur+=${s:i:e-i+1}
    has_cur=1
    i=$((e + 1))
}

gcg_take_tick() {
    local e sub
    gcg_close_tick "$s" $((i + 1))
    e=$GCG_IDX
    sub=${s:i+1:e-i-1}
    gcg_scan "$sub" $((depth + 1))
    cur+=${s:i:e-i+1}
    has_cur=1
    i=$((e + 1))
}

# 展開される heredoc 本文に含まれるコマンド置換だけを解析する。
gcg_subst_scan() {
    local t=$1 d=$2 pre c e sub
    while :; do
        [[ $t == *'$('* || $t == *'`'* ]] || return 0
        pre=${t%%[\`$]*}
        c=${t:${#pre}:1}
        if [[ $pre == *'\' ]]; then
            t=${t:${#pre}+1}
        elif [[ $c == '$' && ${t:${#pre}+1:1} == '(' ]]; then
            gcg_close_paren "$t" $((${#pre} + 2))
            e=$GCG_IDX
            sub=${t:${#pre}+2:e-${#pre}-2}
            gcg_scan "$sub" $((d + 1))
            t=${t:e+1}
        elif [[ $c == '`' ]]; then
            gcg_close_tick "$t" $((${#pre} + 1))
            e=$GCG_IDX
            sub=${t:${#pre}+1:e-${#pre}-1}
            gcg_scan "$sub" $((d + 1))
            t=${t:e+1}
        else
            t=${t:${#pre}+1}
        fi
    done
}

# 現在の語を確定する。リダイレクトの宛先は引数に数えない。
gcg_end_word() {
    if ((has_cur)); then
        if ((hd_mode)); then
            hd_delim+=("$cur")
            hd_strip+=("$((hd_mode == 2))")
            hd_quoted+=("$quoted")
            hd_mode=0
        elif ((here_str)); then
            pipe_text+="$cur"$'\n'
            here_str=0
        elif ((expect_target)); then
            expect_target=0
        else
            words+=("$cur")
        fi
    fi
    cur=""
    has_cur=0
    quoted=0
}

# 単純コマンドを確定して判定する。パイプ以外の区切りでは pipe_text を捨てる。
gcg_end_cmd() {
    gcg_end_word
    if ((${#words[@]} > 0)); then
        GCG_STDIN=$pipe_text
        gcg_eval "$depth" "${words[@]}"
        local -a pw=("${words[@]:1}")
        case ${words[0]##*/} in
        echo) while ((${#pw[@]} > 0)) && [[ ${pw[0]} == -+([neE]) ]]; do pw=("${pw[@]:1}"); done ;;
        printf) ((${#pw[@]} > 0)) && [[ ${pw[0]} == *%* ]] && pw=("${pw[@]:1}") ;;
        esac
        pipe_text+="${pw[*]}"$'\n'
    fi
    words=()
    expect_target=0
    hd_mode=0
    here_str=0
    [[ $1 == '|' ]] || pipe_text=""
}

# 改行に達したとき、保留中の heredoc 本文を読み飛ばして i を終端行の末尾へ進める。
# 行単位で読むのは、巨大な本文に対するパターン照合が二乗時間になるため。
gcg_heredocs() {
    local k line cmp body consumed found delim
    for k in "${!hd_delim[@]}"; do
        delim=${hd_delim[k]}
        body=""
        consumed=0
        found=0
        while IFS= read -r line; do
            consumed=$((consumed + ${#line} + 1))
            cmp=$line
            [[ ${hd_strip[k]} == 1 ]] && cmp=${line##+($'\t')}
            if [[ $cmp == "$delim" ]]; then
                found=1
                break
            fi
            body+=$line$'\n'
        done <<<"${s:i+1}"
        if ((found)); then
            i=$((i + consumed))
        else
            i=$n
        fi
        pipe_text+="$body"
        [[ ${hd_quoted[k]} == 1 ]] || gcg_subst_scan "$body" "$depth"
    done
    hd_delim=()
    hd_strip=()
    hd_quoted=()
}

gcg_scan() {
    local s=$1 depth=$2
    if ((depth > 8)); then
        [[ $s =~ git[[:space:]]+.*config ]] && GCG_DENY=1
        return 0
    fi
    s+=$'\n'
    local n=${#s} i=0 c nx rest pre j ch op2
    local cur="" has_cur=0 quoted=0 expect_target=0 hd_mode=0 here_str=0
    local -a words=() hd_delim=() hd_strip=() hd_quoted=()
    local pipe_text=""

    while ((i < n)); do
        ((GCG_DENY)) && return 0
        c=${s:i:1}
        case $c in
        '\')
            nx=${s:i+1:1}
            if [[ $nx == $'\n' ]]; then
                i=$((i + 2))
                continue
            fi
            cur+=$nx
            has_cur=1
            quoted=1
            i=$((i + 2))
            ;;
        "'")
            rest=${s:i+1}
            pre=${rest%%\'*}
            cur+=$pre
            has_cur=1
            quoted=1
            i=$((i + ${#pre} + 2))
            ;;
        '"')
            has_cur=1
            quoted=1
            i=$((i + 1))
            while ((i < n)); do
                ch=${s:i:1}
                if [[ $ch == '\' ]]; then
                    nx=${s:i+1:1}
                    case $nx in
                    '$' | '`' | '"' | '\') cur+=$nx ;;
                    $'\n') ;;
                    *) cur+="\\$nx" ;;
                    esac
                    i=$((i + 2))
                elif [[ $ch == '"' ]]; then
                    break
                elif [[ $ch == '$' && ${s:i+1:1} == '(' ]]; then
                    gcg_take_paren
                elif [[ $ch == '`' ]]; then
                    gcg_take_tick
                else
                    cur+=$ch
                    i=$((i + 1))
                fi
            done
            i=$((i + 1))
            ;;
        '$')
            nx=${s:i+1:1}
            if [[ $nx == '(' ]]; then
                gcg_take_paren
            elif [[ $nx == "'" ]]; then
                j=$((i + 2))
                while ((j < n)); do
                    ch=${s:j:1}
                    if [[ $ch == '\' ]]; then
                        j=$((j + 2))
                        continue
                    fi
                    [[ $ch == "'" ]] && break
                    j=$((j + 1))
                done
                cur+=${s:i+2:j-i-2}
                has_cur=1
                quoted=1
                i=$((j + 1))
            else
                cur+='$'
                has_cur=1
                i=$((i + 1))
            fi
            ;;
        '`') gcg_take_tick ;;
        ' ' | $'\t')
            gcg_end_word
            i=$((i + 1))
            ;;
        $'\n')
            gcg_end_word
            gcg_heredocs
            gcg_end_cmd ';'
            i=$((i + 1))
            ;;
        ';')
            gcg_end_cmd ';'
            i=$((i + 1))
            ;;
        '&')
            nx=${s:i+1:1}
            if [[ $nx == '&' ]]; then
                gcg_end_cmd '&&'
                i=$((i + 2))
            elif [[ $nx == '>' ]]; then
                gcg_end_word
                expect_target=1
                i=$((i + 2))
                [[ ${s:i:1} == '>' ]] && i=$((i + 1))
            else
                gcg_end_cmd '&'
                i=$((i + 1))
            fi
            ;;
        '|')
            nx=${s:i+1:1}
            if [[ $nx == '|' ]]; then
                gcg_end_cmd '||'
                i=$((i + 2))
            elif [[ $nx == '&' ]]; then
                gcg_end_cmd '|'
                i=$((i + 2))
            else
                gcg_end_cmd '|'
                i=$((i + 1))
            fi
            ;;
        '(' | ')')
            # パイプ直後の "(bash)" で pipe_text を捨てないよう、語がない "(" では確定しない
            if [[ $c == ')' ]] || ((has_cur || ${#words[@]} > 0)); then
                gcg_end_cmd ';'
            fi
            i=$((i + 1))
            ;;
        '<' | '>')
            nx=${s:i+1:1}
            if [[ $nx == '(' ]]; then
                gcg_take_paren
                continue
            fi
            if ((has_cur && !quoted)) && [[ $cur =~ ^[0-9]+$ ]]; then
                cur=""
                has_cur=0
            else
                gcg_end_word
            fi
            if [[ $c == '<' && $nx == '<' ]]; then
                if [[ ${s:i+2:1} == '<' ]]; then
                    here_str=1
                    i=$((i + 3))
                elif [[ ${s:i+2:1} == '-' ]]; then
                    hd_mode=2
                    i=$((i + 3))
                else
                    hd_mode=1
                    i=$((i + 2))
                fi
            else
                expect_target=1
                op2=${s:i:2}
                case $op2 in
                '>>' | '>&' | '>|' | '<&' | '<>') i=$((i + 2)) ;;
                *) i=$((i + 1)) ;;
                esac
            fi
            ;;
        '#')
            if ((has_cur)); then
                cur+='#'
                i=$((i + 1))
            else
                rest=${s:i}
                pre=${rest%%$'\n'*}
                i=$((i + ${#pre}))
            fi
            ;;
        *)
            cur+=$c
            has_cur=1
            i=$((i + 1))
            ;;
        esac
    done
    gcg_end_cmd ';'
}

# w の先頭から "-" で始まる語を読み飛ばす。$1 の空白区切りの語は値を取るので次の語も飛ばす。
# gcg_eval 内からだけ呼ぶ(w / a は動的スコープ)。
gcg_skip_opts() {
    local valopts=" $1 "
    while ((${#w[@]} > 0)); do
        a=${w[0]}
        if [[ $a == -- ]]; then
            w=("${w[@]:1}")
            return 0
        fi
        [[ $a == -?* ]] || return 0
        w=("${w[@]:1}")
        if [[ $valopts == *" $a "* ]]; then
            w=("${w[@]:1}")
        fi
    done
}

# 単純コマンド($2 以降の語)を評価する。前置コマンドを剥がして実体を探す。
gcg_eval() {
    local depth=$1
    shift
    local -a w=("$@")
    local stdin=$GCG_STDIN xargs=0 guard=0 bn a k j c_flag s_flag
    local -a sub
    while ((${#w[@]} > 0 && guard < 30)); do
        guard=$((guard + 1))
        a=${w[0]}
        if [[ $a =~ ^[A-Za-z_][A-Za-z0-9_]*(\[[^]]*\])?\+?= ]]; then
            w=("${w[@]:1}")
            continue
        fi
        bn=${a##*/}
        case $bn in
        if | then | else | elif | do | while | until | '!' | '{' | '}' | time | coproc | nohup | setsid | unbuffer | rtk | proxy | builtin)
            w=("${w[@]:1}")
            gcg_skip_opts ""
            ;;
        command)
            w=("${w[@]:1}")
            case ${w[0]:-} in -v | -V | -pv | -pV) return 0 ;; esac
            gcg_skip_opts ""
            ;;
        exec)
            w=("${w[@]:1}")
            gcg_skip_opts "-a"
            ;;
        env)
            w=("${w[@]:1}")
            for k in "${!w[@]}"; do
                case ${w[k]} in
                -S | --split-string) gcg_scan "${w[k + 1]:-}" $((depth + 1)) ;;
                --split-string=*) gcg_scan "${w[k]#--split-string=}" $((depth + 1)) ;;
                -S?*) gcg_scan "${w[k]#-S}" $((depth + 1)) ;;
                [!-]*) break ;;
                esac
            done
            gcg_skip_opts "-u -C -S --unset --chdir --split-string"
            ;;
        sudo | doas)
            w=("${w[@]:1}")
            gcg_skip_opts "-u -g -h -p -C -D -R -T -U -r -t --user --group --host --prompt --chdir"
            ;;
        nice)
            w=("${w[@]:1}")
            gcg_skip_opts "-n --adjustment"
            ;;
        ionice)
            w=("${w[@]:1}")
            gcg_skip_opts "-c -n -p -P -u"
            ;;
        stdbuf)
            w=("${w[@]:1}")
            gcg_skip_opts "-i -o -e"
            ;;
        timeout)
            w=("${w[@]:1}")
            gcg_skip_opts "-s -k --signal --kill-after"
            w=("${w[@]:1}")
            ;;
        xargs)
            xargs=1
            w=("${w[@]:1}")
            gcg_skip_opts "-I -i -n -P -L -l -d -E -e -s -a --max-args --max-procs --delimiter --arg-file --replace"
            ;;
        watch)
            w=("${w[@]:1}")
            gcg_skip_opts "-n -d --interval"
            gcg_scan "${w[*]}" $((depth + 1))
            return 0
            ;;
        find)
            for k in "${!w[@]}"; do
                case ${w[k]} in
                -exec | -execdir | -ok | -okdir)
                    sub=()
                    j=$((k + 1))
                    while ((j < ${#w[@]})) && [[ ${w[j]} != ';' && ${w[j]} != '+' ]]; do
                        sub+=("${w[j]}")
                        j=$((j + 1))
                    done
                    gcg_eval "$depth" "${sub[@]}"
                    ;;
                esac
            done
            return 0
            ;;
        su | runuser)
            for k in "${!w[@]}"; do
                case ${w[k]} in
                -c | --command) gcg_scan "${w[k + 1]:-}" $((depth + 1)) ;;
                --)
                    gcg_scan "${w[*]:k+1}" $((depth + 1))
                    break
                    ;;
                esac
            done
            return 0
            ;;
        bash | sh | zsh | dash | ash | ksh | mksh)
            w=("${w[@]:1}")
            c_flag=0
            s_flag=0
            while ((${#w[@]} > 0)); do
                a=${w[0]}
                if [[ $a == -- ]]; then
                    w=("${w[@]:1}")
                    break
                fi
                if [[ $a == - ]]; then
                    w=("${w[@]:1}")
                    s_flag=1
                    break
                fi
                [[ $a == [-+]?* ]] || break
                w=("${w[@]:1}")
                if [[ $a == --* ]]; then
                    [[ $a == --rcfile || $a == --init-file ]] && w=("${w[@]:1}")
                    continue
                fi
                [[ $a == -*c* ]] && c_flag=1
                [[ $a == -*s* ]] && s_flag=1
                [[ $a == -o || $a == +o || $a == -O || $a == +O ]] && w=("${w[@]:1}")
            done
            if ((c_flag)); then
                ((${#w[@]} > 0)) && gcg_scan "${w[0]}" $((depth + 1))
            elif ((s_flag || ${#w[@]} == 0)); then
                [[ -n $stdin ]] && gcg_scan "$stdin" $((depth + 1))
            fi
            return 0
            ;;
        eval)
            gcg_scan "${w[*]:1}" $((depth + 1))
            return 0
            ;;
        git)
            gcg_git "$xargs" "${w[@]:1}"
            return 0
            ;;
        docker | podman | nerdctl | kubectl | docker-compose | podman-compose)
            gcg_container "$depth" "${w[@]}"
            return 0
            ;;
        *)
            # 変数やコマンド置換で組み立てたコマンド名は git と仮定する
            if [[ $a == *'$'* || $a == *'`'* ]] && [[ ${w[1]:-} == config ]]; then
                gcg_config "$xargs" "${w[@]:2}"
            fi
            # 未知のラッパー(flock / strace / tmux 等)は後続の git 語と、空白を含む語(コマンド文字列)を調べる
            case $bn in
            echo | printf | grep | egrep | fgrep | rg | ag | cat | jq | yq | head | tail | wc | sed | awk | cut | sort | uniq | tee | ls | cd | test | '[' | '[[' | true | false | read | gh | diff | cmp | tr | less | man | which | type | basename | dirname | mkdir | touch | cp | mv | rm | ln | chmod | chown | stat | file | date | sleep | kill | wait | export | local | declare | readonly | unset | set | shift | return | exit | break | continue | alias | unalias | pwd | realpath | readlink) ;;
            *)
                for ((k = 1; k < ${#w[@]}; k++)); do
                    c_flag=${w[k]}
                    if [[ ${c_flag##*/} == git ]]; then
                        gcg_git "$xargs" "${w[@]:k+1}"
                    elif [[ $c_flag == *[[:space:]]* ]]; then
                        gcg_scan "$c_flag" $((depth + 1))
                    fi
                done
                ;;
            esac
            return 0
            ;;
        esac
    done
    return 0
}

# git の引数(グローバルオプションを含む)から config サブコマンドを探して判定する。
gcg_git() {
    local xargs=$1
    shift
    while (($# > 0)); do
        # -c alias.x=!cmd は cmd をシェルで実行する(depth は gcg_eval から動的スコープで参照)
        if [[ $1 == -c && ${2:-} == [Aa][Ll][Ii][Aa][Ss].*=!* ]]; then
            gcg_scan "${2#*=!}" $((depth + 1))
        fi
        case $1 in
        -C | -c | --git-dir | --work-tree | --namespace | --super-prefix | --config-env | --attr-source)
            shift
            (($# > 0)) && shift
            ;;
        -*) shift ;;
        *) break ;;
        esac
    done
    [[ ${1:-} == config ]] || return 0
    shift
    gcg_config "$xargs" "$@"
}

# git config の引数を判定し、書き込みなら gcg_write に渡す。
# 位置引数(オプションと、値を取るオプションの値を除く)が 2 個以上ならオプションの
# 内容に関わらず書き込みとみなす。--get 等を個別に許すと、末尾に付けて分類を偽装する
# 回避策(例: user.name attacker --get x)を許してしまうため。
gcg_config() {
    local xargs=$1
    shift
    local -a args=("$@")
    local a o k pos=0 first="" write=0 read=0 glob=0 other=0 end=0 scope=other
    for ((k = 0; k < ${#args[@]}; k++)); do
        a=${args[k]}
        if ((end)); then
            pos=$((pos + 1))
            continue
        fi
        case $a in
        --) end=1 ;;
        --global | --system) glob=1 ;;
        --local | --worktree) other=1 ;;
        --file | -f | --blob)
            other=1
            k=$((k + 1))
            ;;
        --file=* | --blob=*) other=1 ;;
        --default | --type | --comment) k=$((k + 1)) ;;
        --get | --get-all | --get-regexp | --get-urlmatch | --list | -l | --get-color | --get-colorbool) read=1 ;;
        --*)
            # git は曖昧でない限り長いオプションの省略形を受け付けるため前方一致で見る
            for o in --unset-all --unset --remove-section --rename-section --edit; do
                if ((${#a} >= 3)) && [[ $o == "$a"* ]]; then
                    write=1
                fi
            done
            ;;
        -*) [[ $a == -*e* ]] && write=1 ;;
        *)
            pos=$((pos + 1))
            ((pos == 1)) && first=$a
            ;;
        esac
    done
    # git 2.46 以降のサブコマンド形式(キーは必ず "." を含むので衝突しない)
    case $first in
    set | unset | edit | rename-section | remove-section) write=1 ;;
    get | list) pos=0 ;;
    esac
    ((glob && !other)) && scope=global
    if ((write || pos >= 2)) || ((xargs && !read)); then
        gcg_write "$scope"
    fi
    return 0
}

# コンテナ内のファイルシステムだけに閉じる書き込みは許可し、それ以外は拒否する。
# free: ホストのパスをマウントしていない。global_only: マウントはあるが HOME や
# gitconfig ではないため、--global / --system(コンテナの HOME 側)だけ許可する。
gcg_write() {
    case $GCG_CONTAINER in
    free) return 0 ;;
    global_only) [[ $1 == global ]] && return 0 ;;
    esac
    GCG_DENY=1
}

# $1 が HOME・その祖先・gitconfig を含みうるパスなら 0 を返す。判断できない展開は 0 とする。
# $PWD や "." は作業ディレクトリ(GCG_CWD、なければこのプロセスの PWD)に解決して判定する。
# 作業ディレクトリが HOME やその祖先なら、プロジェクトのマウントでも HOME のマウントになる。
gcg_homeish() {
    local p=$1 h=${HOME:-/nonexistent} cwd=${GCG_CWD:-$PWD}
    # 相対パスの cwd は意味を持たないので、このプロセスの PWD に戻す
    [[ $cwd == /* ]] || cwd=$PWD
    case $p in
    '$PWD' | '$PWD'/*) p="$cwd${p:4}" ;;
    '${PWD}' | '${PWD}'/*) p="$cwd${p:6}" ;;
    '$(pwd)' | '$(pwd)'/*) p="$cwd${p:6}" ;;
    '`pwd`' | '`pwd`'/*) p="$cwd${p:5}" ;;
    . | ./*) p="$cwd${p:1}" ;;
    '~' | '~'/*) p="$h${p:1}" ;;
    '$HOME' | '$HOME'/*) p="$h${p:5}" ;;
    '${HOME}' | '${HOME}'/*) p="$h${p:7}" ;;
    esac
    [[ $p == *'$'* || $p == *'`'* || $p == *'..'* ]] && return 0
    while [[ $p == *//* ]]; do p=${p//\/\//\/}; done
    while [[ $p == */./* ]]; do p=${p//\/.\//\/}; done
    while [[ $p == */. || $p == */ ]]; do
        p=${p%/.}
        p=${p%/}
    done
    [[ -z $p ]] && return 0
    [[ $p == "$h" || $h == "$p"/* ]] && return 0
    [[ $p == *.gitconfig || $p == */.config || $p == */.config/git || $p == */.config/git/* ]] && return 0
    return 1
}

# docker/podman run の引数から GCG_MODE(free / global_only / host)を決める。
# 読み取り専用マウントは書き込めないので無視する。--volumes-from は中身が分からないため host。
gcg_mounts_mode() {
    GCG_MODE=free
    local -a a=("$@")
    local k spec kind src dst opts f ro type
    for ((k = 0; k < ${#a[@]}; k++)); do
        spec=""
        kind=""
        case ${a[k]} in
        --volumes-from | --volumes-from=*)
            GCG_MODE=host
            return 0
            ;;
        -v | --volume)
            kind=v
            spec=${a[k + 1]:-}
            k=$((k + 1))
            ;;
        --mount)
            kind=m
            spec=${a[k + 1]:-}
            k=$((k + 1))
            ;;
        --volume=*)
            kind=v
            spec=${a[k]#*=}
            ;;
        --mount=*)
            kind=m
            spec=${a[k]#*=}
            ;;
        -v=*)
            kind=v
            spec=${a[k]#-v=}
            ;;
        -[a-uw-zA-Z]*v)
            kind=v
            spec=${a[k + 1]:-}
            k=$((k + 1))
            ;;
        -v?*)
            kind=v
            spec=${a[k]#-v}
            ;;
        *) continue ;;
        esac
        src=""
        ro=0
        if [[ $kind == v ]]; then
            IFS=: read -r src dst opts <<<"$spec"
            [[ -n $dst ]] || continue
            [[ ",$opts," == *,ro,* ]] && ro=1
            case $src in
            /* | '~'* | .* | '$'* | '`'*) ;;
            *) continue ;;
            esac
        else
            type=""
            local -a fields
            IFS=, read -ra fields <<<"$spec"
            for f in "${fields[@]}"; do
                case $f in
                type=*) type=${f#type=} ;;
                source=* | src=*) src=${f#*=} ;;
                ro | readonly | ro=true | ro=1 | readonly=true | readonly=1) ro=1 ;;
                esac
            done
            [[ $type == bind && -n $src ]] || continue
        fi
        ((ro)) && continue
        if gcg_homeish "$src"; then
            GCG_MODE=host
            return 0
        fi
        GCG_MODE=global_only
    done
}

# docker / podman / nerdctl / kubectl 等の引数から、コンテナ内で実行されるコマンドを探して評価する。
# run / create だけはマウントを見て書き込みの扱いを決める。exec や compose はマウントが
# コマンドから分からないため、ホストと同じ扱い(拒否)のままにする。
gcg_container() {
    local depth=$1 saved=$GCG_CONTAINER
    shift
    local -a c=("$@")
    local i k verb="" mode=host a b
    for ((i = 1; i < ${#c[@]}; i++)); do
        case ${c[i]} in
        --context | -H | --host | --config | --log-level | --namespace | -n | --kubeconfig | --cluster | --user | -c) i=$((i + 1)) ;;
        -*) ;;
        *)
            verb=${c[i]}
            break
            ;;
        esac
    done
    case ${c[0]##*/} in
    docker | podman | nerdctl)
        if [[ $verb == run || $verb == create ]]; then
            gcg_mounts_mode "${c[@]:i+1}"
            mode=$GCG_MODE
        fi
        ;;
    esac
    GCG_CONTAINER=$mode
    for ((k = i + 1; k < ${#c[@]}; k++)); do
        a=${c[k]}
        b=${a##*/}
        case $b in
        git | bash | sh | zsh | dash | ash | ksh | env | sudo | command | eval | xargs | timeout | nohup | find | su)
            gcg_eval "$depth" "${c[@]:k}"
            # --entrypoint <cmd> <image> <args...> の形では画像名の次から引数が続く
            if [[ ${c[k - 1]} == --entrypoint ]]; then
                gcg_eval "$depth" "$a" "${c[@]:k+2}"
            fi
            ;;
        --entrypoint=git | --entrypoint=*/git | --entrypoint=bash | --entrypoint=sh | --entrypoint=*/bash | --entrypoint=*/sh)
            gcg_eval "$depth" "${a#--entrypoint=}" "${c[@]:k+2}"
            ;;
        esac
    done
    GCG_CONTAINER=$saved
}
