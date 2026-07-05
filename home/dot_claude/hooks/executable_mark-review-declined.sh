#!/bin/bash

# ユーザーが明示的にレビュー未解決警告への対応を拒否した際、
# 同一セッション内で同じ PR について再警告しないよう記録する。
# require-review-thread-fixes.sh の Stop hook から参照される。

PR_NUMBER="${1:?Usage: mark-review-declined.sh <PR_NUMBER>}"
SESSION_ID="${CLAUDE_CODE_SESSION_ID:?CLAUDE_CODE_SESSION_ID is not set}"

# PR_NUMBER が数値でない場合、jq --argjson に渡すと不正な JSON として失敗する。
# シェルリダイレクトは jq の成否に関わらずファイルを先に truncate してしまうため、
# 検証を怠ると既存の declined_prs が失われる。
if [[ ! "$PR_NUMBER" =~ ^[0-9]+$ ]]; then
    echo "Error: PR_NUMBER must be a positive integer, got: ${PR_NUMBER}" >&2
    exit 1
fi

# SESSION_ID をそのままファイル名に埋め込むため、パス区切り文字や `..` を
# 含む値を拒否する（ディレクトリトラバーサル対策）
if [[ ! "$SESSION_ID" =~ ^[A-Za-z0-9._-]+$ ]]; then
    echo "Error: CLAUDE_CODE_SESSION_ID contains invalid characters" >&2
    exit 1
fi

DATA_DIR="$HOME/.claude/data"
DECLINE_FILE="$DATA_DIR/review-declined-${SESSION_ID}.json"
TMP_FILE="${DECLINE_FILE}.tmp.$$"

mkdir -p "$DATA_DIR" && chmod 700 "$DATA_DIR"

EXISTING=$(cat "$DECLINE_FILE" 2>/dev/null || echo '{"declined_prs":[]}')
# 一時ファイルに書き出してから mv することで、jq 失敗時に既存ファイルを
# 空で上書きしてしまう事態を防ぐ（アトミックな置き換え）。
# declined_prs が欠落・null・配列以外（壊れたデータ）の場合も [] として
# 復旧できるよう type チェックしてから追加する
if ! jq --argjson pr "$PR_NUMBER" \
    '.declined_prs = ((if (.declined_prs | type) == "array" then .declined_prs else [] end) + [$pr] | unique)' \
    <<< "$EXISTING" > "$TMP_FILE"; then
    echo "Error: failed to update ${DECLINE_FILE}" >&2
    rm -f "$TMP_FILE"
    exit 1
fi
if ! mv "$TMP_FILE" "$DECLINE_FILE"; then
    echo "Error: failed to move ${TMP_FILE} to ${DECLINE_FILE}" >&2
    rm -f "$TMP_FILE"
    exit 1
fi
if ! chmod 600 "$DECLINE_FILE"; then
    echo "Error: failed to set permissions on ${DECLINE_FILE}" >&2
    exit 1
fi

echo "PR #${PR_NUMBER} marked as declined for this session (${SESSION_ID})."
