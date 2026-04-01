#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: gh-pr-target-repo.sh [--remote]

Resolve the preferred GitHub repository for pull request creation.
- If `upstream` exists and points to GitHub, prefer it
- Otherwise use `origin`
- If neither remote can be resolved, fall back to `gh repo view`

Options:
  --remote  Print the preferred remote name instead of owner/repo
EOF
}

OUTPUT_MODE="repo"
if [[ $# -gt 1 ]]; then
  usage >&2
  exit 1
fi

if [[ $# -eq 1 ]]; then
  case "$1" in
    --remote)
      OUTPUT_MODE="remote"
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 1
      ;;
  esac
fi

remote_to_repo() {
  local remote_name="$1"
  local remote_url

  remote_url=$(git remote get-url "$remote_name" 2>/dev/null || true)
  if [[ -z "$remote_url" ]]; then
    return 1
  fi

  case "$remote_url" in
    git@github.com:*)
      remote_url="${remote_url#git@github.com:}"
      ;;
    https://github.com/*)
      remote_url="${remote_url#https://github.com/}"
      ;;
    ssh://git@github.com/*)
      remote_url="${remote_url#ssh://git@github.com/}"
      ;;
    *)
      return 1
      ;;
  esac

  remote_url="${remote_url%.git}"

  if [[ "$remote_url" != */* ]]; then
    return 1
  fi

  printf '%s\n' "$remote_url"
}

PREFERRED_REMOTE=""
PREFERRED_REPO=""

for candidate in upstream origin; do
  if repo=$(remote_to_repo "$candidate"); then
    PREFERRED_REMOTE="$candidate"
    PREFERRED_REPO="$repo"
    break
  fi
done

if [[ -z "$PREFERRED_REPO" ]]; then
  PREFERRED_REPO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner')
fi

if [[ -z "$PREFERRED_REPO" ]]; then
  echo "Error: Could not resolve GitHub repository for pull request target" >&2
  exit 1
fi

if [[ "$OUTPUT_MODE" == "remote" ]]; then
  if [[ -z "$PREFERRED_REMOTE" ]]; then
    echo "Error: Could not resolve git remote for pull request target" >&2
    exit 1
  fi
  printf '%s\n' "$PREFERRED_REMOTE"
else
  printf '%s\n' "$PREFERRED_REPO"
fi
