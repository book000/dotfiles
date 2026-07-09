#!/bin/bash

# PostToolUse hook: deep-review / lite-review スキル実行後に指摘事項の対応を促す。
# スコア 50 以上の指摘が残っている場合に Claude の処理をブロックする。
# 副作用として findings を ~/.claude/data/deep-review-state.json に書き出す。
# これにより Stop hook (deep-review-require-fixes.sh) がトランスクリプトを
# パースせずステートファイルから確実に判定できる。

STATE_DIR="$HOME/.claude/data"

# stdin から JSON を読み込む（公式フック契約: stdin JSON）
INPUT=$(cat)

# Skill ツールの実行か確認する
TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null)
if [[ "$TOOL_NAME" != "Skill" ]]; then
    exit 0
fi

# deep-review / lite-review スキル以外はスキップする
SKILL=$(printf '%s' "$INPUT" | jq -r '.tool_input.skill_name // .tool_input.skill // ""' 2>/dev/null)
if [[ "$SKILL" != "deep-review" && "$SKILL" != "lite-review" ]]; then
    exit 0
fi

# セッション ID を取得する
SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // ""' 2>/dev/null)

# セッション ID が英数字・ハイフン・アンダースコアのみで構成されているか検証する。
# 空文字、または `/` や `..` を含む不正な値をファイルパスへ直接展開すると
# 意図しないディレクトリへの書き込みや書き込み失敗を招くため、
# 一致しない場合は後方互換のため旧形式の固定パスにフォールバックする。
if [[ "$SESSION_ID" =~ ^[A-Za-z0-9_-]+$ ]]; then
    STATE_FILE="$STATE_DIR/deep-review-state-${SESSION_ID}.json"
else
    STATE_FILE="$STATE_DIR/deep-review-state.json"
fi

# tool_response からスコアを抽出する
# grep -oP（PCRE）は macOS の BSD grep では動かないため grep -E + sed で代替する
TOOL_RESPONSE=$(printf '%s' "$INPUT" | jq -r '.tool_response // ""' 2>/dev/null)
mapfile -t SCORES < <(printf '%s' "$TOOL_RESPONSE" | grep -E 'Score:[[:space:]]*[0-9]+' | sed 's/.*Score:[[:space:]]*//' | grep -E '^[0-9]+')

# スコア 50 以上の指摘をカウントする
HIGH_SCORE_COUNT=0
MAX_SCORE=0
for score in "${SCORES[@]}"; do
    if [[ -n "$score" && "$score" -ge 50 ]]; then
        HIGH_SCORE_COUNT=$((HIGH_SCORE_COUNT + 1))
        if [[ "$score" -gt "$MAX_SCORE" ]]; then
            MAX_SCORE="$score"
        fi
    fi
done

# ステートファイルに結果を書き出す（Stop hook が使用）
# ディレクトリはオーナーのみアクセス可能 (700) で作成する
# mkdir -p と -m の組み合わせは最深ディレクトリにしか適用されないため分割する（SC2174）
mkdir -p "$STATE_DIR" && chmod 700 "$STATE_DIR"

# セッション毎ファイルへの分割により書き込みのたびにファイルが増えるため、
# TTL（24時間、Stop hook の STATE_TTL と同一）を超えた期限切れファイルを
# 都度削除し、無制限な蓄積を防ぐ。旧形式の固定名ファイルは対象外。
find "$STATE_DIR" -maxdepth 1 -name 'deep-review-state-*.json' -mmin +1440 -delete 2>/dev/null

if ! jq -n \
    --arg session_id "$SESSION_ID" \
    --arg skill "$SKILL" \
    --argjson high_score_count "$HIGH_SCORE_COUNT" \
    --argjson max_score "$MAX_SCORE" \
    --argjson timestamp "$(date +%s)" \
    '{
        session_id: $session_id,
        skill: $skill,
        timestamp: $timestamp,
        high_score_count: $high_score_count,
        max_score: $max_score
    }' > "$STATE_FILE"; then
    echo "ERROR: Failed to write $SKILL state to $STATE_FILE" >&2
    # PostToolUse ブロックは機能しているため続行する。Stop hook での再検証はスキップされる。
fi
# ステートファイルはオーナーのみ読み書き可能 (600) にする
chmod 600 "$STATE_FILE" 2>/dev/null

# スコア 50 以上の指摘がある場合はブロックして対応を促す
if [[ "$HIGH_SCORE_COUNT" -gt 0 ]]; then
    REASON="🔔 ${SKILL} で ${HIGH_SCORE_COUNT} 件の重要な指摘事項が見つかりました（最高スコア: ${MAX_SCORE}）。

CLAUDE.md の規則により、スコア 50 以上の指摘事項に必ず対応してください。

対応手順:
1. スコア 50 以上の指摘をすべて確認する
2. 各指摘に対して適切な修正を実施する
3. 修正内容をコミット・プッシュする
4. PR 本文を更新する
5. 必要に応じて再度 /${SKILL} を実施する

対応漏れは禁止されています。"
    jq -n --arg reason "$REASON" '{"decision":"block","reason":$reason}'
    exit 0
fi

# スコア情報はあるが全件 50 未満の場合
TOTAL="${#SCORES[@]}"
if [[ "$TOTAL" -gt 0 ]]; then
    jq -n --arg skill "$SKILL" --argjson total "$TOTAL" '{"decision":"approve","reason":($skill + ": " + ($total | tostring) + " 件の指摘がありましたが、すべてスコア 50 未満です。")}'
    exit 0
fi

exit 0
