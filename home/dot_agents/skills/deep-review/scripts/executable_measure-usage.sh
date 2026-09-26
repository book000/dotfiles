#!/usr/bin/env bash
# deep-review のトークン消費を、既存の Claude Code セッショントランスクリプト (JSONL) の
# 事後解析のみから計測する、読み取り専用・副作用なしのスクリプト (新規計装は行わない、YAGNI)。
#
# 使い方:
#   measure-usage.sh --stage <name>:<path>[,<path>...] [--stage ...] [--format markdown|json|both]
#
# 段階分けは呼び出し側の責務: このスクリプトは「渡されたグループごとに集計する」だけの
# 汎用ツールであり、Step1-4/Step5/Step6 等の自動判別は行わない。
#
# sub-agent トランスクリプトの対応付け:
#   `isolation: "worktree"` の sub-agent は専用の project-slug ディレクトリに新規セッションファイルを作る。
#   ディレクトリ名は親の project-slug に worktree 相対パスを `--` 区切りで付加したもの
#   (例: ~/.claude/projects/-mnt-ssd-...--claude-worktrees-issue-391/)。
#   `isolation` 未指定の通常 dispatch は親と同一 project-slug ディレクトリに、親のセッション
#   開始時刻以降に作成された新規 jsonl ファイルとして現れる。対応関係が一意に定まらない場合
#   (複数候補が同時刻帯にある等) は、候補の jsonl ファイルをすべて列挙する。
#   列挙対象はその project-slug ディレクトリ内で親セッション開始時刻以降に作られたファイルで、
#   実行者が目視で選ぶ。
#
# 欠損フィールドはエラー終了せず "N/A" (JSON では null) として扱う。
# 指摘 class 内訳は、渡されたファイル内のリテラル文字列出現数によるヒューリスティックであり、
# 権威あるソースではない (真の状態は `ledger.sh show <session>` を参照すること)。

set -euo pipefail

die() { echo "ERROR: $*" >&2; exit 1; }

NOTE="Note: these are processed-token counts derived from session transcripts, not API billing or plan-quota usage. The finding class breakdown below is a heuristic literal-string count over the transcript text, not the authoritative ledger state (use ledger.sh show for that)."

FORMAT="both"
declare -a STAGE_NAMES=()
declare -a STAGE_PATHS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --stage)
            [[ $# -ge 2 ]] || die "usage: --stage <name>:<path>[,<path>...]"
            spec="$2"
            name="${spec%%:*}"
            paths="${spec#*:}"
            [[ -n "$name" && "$name" != "$spec" ]] || die "invalid --stage spec (expected name:path): $spec"
            STAGE_NAMES+=("$name")
            STAGE_PATHS+=("$paths")
            shift 2
            ;;
        --format)
            [[ $# -ge 2 ]] || die "usage: --format markdown|json|both"
            FORMAT="$2"
            shift 2
            ;;
        *)
            die "unknown argument: $1"
            ;;
    esac
done

[[ "${#STAGE_NAMES[@]}" -gt 0 ]] || die "at least one --stage is required"
[[ "$FORMAT" =~ ^(markdown|json|both)$ ]] || die "invalid --format: $FORMAT"

# jq フィルタは意図的にシングルクォートで渡す
# shellcheck disable=SC2016
STAGE_FILTER='
  def numor0: if type == "number" then . else 0 end;
  def sumfield(f): (map(f)) as $x | if ($x | all(. == null)) then null else ($x | map(numor0) | add) end;
  [ .[] | select(.type == "assistant") ] as $msgs
  | {
      invocation_count: ($msgs | length),
      input_tokens: ($msgs | sumfield(.message.usage.input_tokens // null)),
      cache_creation_input_tokens: ($msgs | sumfield(.message.usage.cache_creation_input_tokens // null)),
      cache_read_input_tokens: ($msgs | sumfield(.message.usage.cache_read_input_tokens // null)),
      output_tokens: ($msgs | sumfield(.message.usage.output_tokens // null)),
      models: ($msgs | map(.message.model // "N/A") | group_by(.) | map({model: .[0], count: length})),
      first_ts: ([$msgs[].timestamp // empty] | sort | first // null),
      last_ts: ([$msgs[].timestamp // empty] | sort | last // null),
      sendmessage_targets: ([$msgs[] | (.message.content // [])[]? | select(.type == "tool_use" and .name == "SendMessage") | (.input.to // "N/A")] | group_by(.) | map({to: .[0], count: length}))
    }
'
EMPTY_STAGE='{"invocation_count":0,"input_tokens":null,"cache_creation_input_tokens":null,"cache_read_input_tokens":null,"output_tokens":null,"models":[],"first_ts":null,"last_ts":null,"sendmessage_targets":[]}'

to_epoch() {
    # ISO8601 タイムスタンプ (小数秒あり) を秒精度の epoch に変換する。失敗時は空文字を返す。
    date -u -d "${1/%.[0-9]*Z/Z}" +%s 2>/dev/null || true
}

STAGES_JSON=()
for i in "${!STAGE_NAMES[@]}"; do
    name="${STAGE_NAMES[$i]}"
    IFS=',' read -r -a files <<<"${STAGE_PATHS[$i]}"
    existing=()
    for f in "${files[@]}"; do
        if [[ -f "$f" ]]; then
            existing+=("$f")
        else
            echo "WARNING: file not found, skipping: $f" >&2
        fi
    done

    if [[ "${#existing[@]}" -eq 0 ]]; then
        stage_data="$EMPTY_STAGE"
        findings_merge_blocker=0
        findings_follow_up=0
        findings_unverified=0
        findings_out_of_scope=0
    else
        # transcript 内では JSON がツール呼び出し文字列としてもう一段エンコードされ、
        # 引用符が `\"` にエスケープされていることがあるため、両形を許容する。
        jq_err=$(mktemp)
        stage_data=$(jq -s "$STAGE_FILTER" "${existing[@]}" 2>"$jq_err")
        jq_status=$?
        if [[ $jq_status -ne 0 ]]; then
            echo "WARNING: jq failed for stage '$name': $(cat "$jq_err")" >&2
            stage_data="$EMPTY_STAGE"
        fi
        rm -f "$jq_err"

        # 4 クラス分の指摘件数を 1 回の grep で集計する (ファイル数分の走査を 1 回に抑える)。
        grep_err=$(mktemp)
        class_matches=$(grep -Eo \
            -e '"class\\?":\\?"merge-blocker' \
            -e '"class\\?":\\?"follow-up' \
            -e '"class\\?":\\?"unverified' \
            -e '"class\\?":\\?"out-of-scope' \
            "${existing[@]}" 2>"$grep_err")
        grep_status=$?
        if [[ $grep_status -eq 2 ]]; then
            echo "WARNING: grep failed reading file(s) for stage '$name': $(cat "$grep_err")" >&2
        fi
        rm -f "$grep_err"

        findings_merge_blocker=$(grep -c 'merge-blocker$' <<<"$class_matches" || true)
        findings_follow_up=$(grep -c 'follow-up$' <<<"$class_matches" || true)
        findings_unverified=$(grep -c 'unverified$' <<<"$class_matches" || true)
        findings_out_of_scope=$(grep -c 'out-of-scope$' <<<"$class_matches" || true)
    fi

    first_ts=$(echo "$stage_data" | jq -r '.first_ts // empty')
    last_ts=$(echo "$stage_data" | jq -r '.last_ts // empty')
    duration_seconds="null"
    if [[ -n "$first_ts" && -n "$last_ts" ]]; then
        start_epoch=$(to_epoch "$first_ts")
        end_epoch=$(to_epoch "$last_ts")
        if [[ -n "$start_epoch" && -n "$end_epoch" ]]; then
            duration_seconds=$((end_epoch - start_epoch))
        fi
    fi

    STAGES_JSON+=("$(jq -n \
        --arg name "$name" \
        --argjson data "$stage_data" \
        --argjson duration "$duration_seconds" \
        --argjson mb "$findings_merge_blocker" \
        --argjson fu "$findings_follow_up" \
        --argjson uv "$findings_unverified" \
        --argjson oos "$findings_out_of_scope" \
        '$data + {name: $name, duration_seconds: $duration, findings: {merge_blocker: $mb, follow_up: $fu, unverified: $uv, out_of_scope: $oos}}')")
done

STAGES_ARRAY_JSON=$(printf '%s\n' "${STAGES_JSON[@]}" | jq -s '.')
FULL_JSON=$(jq -n --arg note "$NOTE" --argjson stages "$STAGES_ARRAY_JSON" '{note: $note, stages: $stages}')

nz() {
    local v="$1"
    [[ "$v" == "null" || -z "$v" ]] && echo "N/A" || echo "$v"
}

print_markdown() {
    echo "## deep-review token usage"
    echo
    echo "| stage | invocations | input | cache_creation | cache_read | output | duration(s) | merge-blocker | follow-up | unverified | out-of-scope |"
    echo "|---|---|---|---|---|---|---|---|---|---|---|"
    echo "$FULL_JSON" | jq -r '.stages[] | [.name, .invocation_count, (.input_tokens // "N/A"), (.cache_creation_input_tokens // "N/A"), (.cache_read_input_tokens // "N/A"), (.output_tokens // "N/A"), (.duration_seconds // "N/A"), .findings.merge_blocker, .findings.follow_up, .findings.unverified, .findings.out_of_scope] | @tsv' |
        while IFS=$'\t' read -r n inv it cc cr ot dur mb fu uv oos; do
            echo "| $n | $inv | $it | $cc | $cr | $ot | $dur | $mb | $fu | $uv | $oos |"
        done
    echo
    echo "### models per stage"
    echo
    echo "$FULL_JSON" | jq -r '.stages[] | .name as $n | .models[] | "- \($n): \(.model) x \(.count)"'
    echo
    echo "### SendMessage targets per stage (idle→nudge→再dispatch 検出用)"
    echo
    echo "$FULL_JSON" | jq -r '.stages[] | .name as $n | .sendmessage_targets[] | "- \($n): \(.to) x \(.count)"'
    echo
    echo "$NOTE"
}

case "$FORMAT" in
    markdown)
        print_markdown
        ;;
    json)
        echo "$FULL_JSON"
        ;;
    both)
        print_markdown
        echo
        echo '```json'
        echo "$FULL_JSON"
        echo '```'
        ;;
esac
