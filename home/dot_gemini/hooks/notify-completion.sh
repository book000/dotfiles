#!/usr/bin/env bash
set -euo pipefail

INPUT_JSON=$(cat)

SESSION_ID=${GEMINI_SESSION_ID:-}
CWD_PATH=${GEMINI_CWD:-}
if command -v jq >/dev/null 2>&1; then
  SESSION_ID=$(echo "$INPUT_JSON" | jq -r '.session_id // empty' 2>/dev/null || true)
  CWD_PATH=$(echo "$INPUT_JSON" | jq -r '.cwd // empty' 2>/dev/null || true)
fi

if [[ -z "$SESSION_ID" ]]; then
  SESSION_ID=${GEMINI_SESSION_ID:-""}
fi
if [[ -z "$CWD_PATH" ]]; then
  CWD_PATH=${GEMINI_CWD:-""}
fi

config="${HOME}/.config/notify/gemini.env"
if [[ -f "$config" ]]; then
  # shellcheck source=/dev/null
  source "$config"
fi

if [[ -z "${DISCORD_WEBHOOK_URL:-}" ]]; then
  printf '{}\n'
  exit 0
fi

timestamp=$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")
hostname_val=$(hostname)

fields=$(jq -n \
  --arg cwd "$CWD_PATH" \
  --arg sid "$SESSION_ID" \
  '[
    {name: "📁 実行ディレクトリ", value: ($cwd|if .=="" then "(unknown)" else . end), inline: true},
    {name: "🆔 セッションID", value: ($sid|if .=="" then "(unknown)" else . end), inline: true}
  ]')

mention=""
if [[ -n "${DISCORD_MENTION_USER_ID:-}" ]]; then
  mention="<@${DISCORD_MENTION_USER_ID}> "
fi

payload=$(jq -n \
  --arg content "${mention}Gemini CLI Finished (${hostname_val})" \
  --arg title "Gemini CLI セッション完了" \
  --arg ts "$timestamp" \
  --argjson fields "$fields" \
  '{
    content: $content,
    embeds: [
      {
        title: $title,
        color: 5763719,
        timestamp: $ts,
        fields: $fields
      }
    ]
  }')

curl -fsS -H "Content-Type: application/json" -d "$payload" "$DISCORD_WEBHOOK_URL" >/dev/null

printf '{}\n'
