#!/bin/bash
# AI エージェント設定ファイルの JSON Schema バリデーション

set -euo pipefail

echo "Validating AI agent configuration files..."

# Codex の modify_ テンプレートを評価するため chezmoi を用意する。
if ! command -v chezmoi &> /dev/null; then
  CHEZMOI_BIN_DIR=$(mktemp -d)
  trap 'rm -rf "$CHEZMOI_BIN_DIR"' EXIT
  curl -sfL --retry 5 --retry-delay 5 https://git.io/chezmoi | sh -s -- -b "$CHEZMOI_BIN_DIR"
  PATH="$CHEZMOI_BIN_DIR:$PATH"
fi

# check-jsonschema のインストール確認
if ! command -v check-jsonschema &> /dev/null; then
  echo "Installing check-jsonschema..."
  pip install check-jsonschema
fi

FAILED=0
FILES_CHECKED=0

# Claude Code settings.json (公式スキーマを使用)
if [ -f "home/dot_claude/settings.json" ]; then
  echo "Validating Claude Code settings.json..."
  if ! check-jsonschema --schemafile https://json.schemastore.org/claude-code-settings.json home/dot_claude/settings.json; then
    echo "❌ Claude Code settings.json validation failed"
    FAILED=1
  else
    echo "✅ Claude Code settings.json validation passed"
  fi
  FILES_CHECKED=$((FILES_CHECKED + 1))
fi

# Codex CLI config.toml modify template
if [ -f "home/dot_codex/modify_private_config.toml" ]; then
  echo "Validating Codex CLI config.toml..."
  CODEX_CONFIG_INPUT=$(mktemp)
  trap 'rm -rf "${CHEZMOI_BIN_DIR:-}" "$CODEX_CONFIG_INPUT"' EXIT
  printf '%s\n' \
    'web_search = "disabled"' \
    'model = "gpt-5.4"' \
    'model_reasoning_effort = "medium"' \
    '[projects."/tmp/codex-runtime-state"]' \
    'trust_level = "trusted"' \
    '[hooks.state."/tmp/codex-runtime-hook"]' \
    'trusted_hash = "sha256:test"' \
    '[notice.model_migrations]' \
    'gpt_5_4 = "gpt-5.6"' \
    '[features]' \
    'codex_hooks = false' \
    'remote_control = true' > "$CODEX_CONFIG_INPUT"
  if ! chezmoi execute-template --file --with-stdin home/dot_codex/modify_private_config.toml < "$CODEX_CONFIG_INPUT" | python3 -c '
import sys

try:
    import tomllib
except ModuleNotFoundError:
    try:
        import tomli as tomllib
    except ModuleNotFoundError:
        raise SystemExit("tomllib or tomli is required to validate TOML but is not installed.")

config = tomllib.loads(sys.stdin.read())
assert config["web_search"] == "live"
assert config["model"] == "gpt-5.4"
assert config["model_reasoning_effort"] == "medium"
assert config["features"]["hooks"] is True
assert config["features"]["remote_control"] is True
assert "codex_hooks" not in config["features"]
assert config["shell_environment_policy"]["set"]["BASH_ENV"].endswith("/.bash_env")
assert config["projects"]["/tmp/codex-runtime-state"]["trust_level"] == "trusted"
assert config["hooks"]["state"]["/tmp/codex-runtime-hook"]["trusted_hash"] == "sha256:test"
state = config["hooks"]["state"]
dispatcher = [(k, v) for k, v in state.items() if k.endswith("/.codex/hooks.json:pre_tool_use:0:0")]
git_guard = [(k, v) for k, v in state.items() if k.endswith("/.codex/hooks.json:pre_tool_use:0:1")]
assert len(dispatcher) == 1
assert dispatcher[0][1]["trusted_hash"] == "sha256:8863117dfc0f0ed890109dff2a9c7eaa3076dd94ed001602d3de33ef7517dbdc"
assert len(git_guard) == 1
assert git_guard[0][1]["trusted_hash"] == "sha256:5be52eb577c8c54cec54e7635c1fb9ad3fa4166798f3652f0444a50a5fadf979"
assert config["notice"]["model_migrations"]["gpt_5_4"] == "gpt-5.6"
'
  then
    echo "❌ Codex CLI config.toml validation failed"
    FAILED=1
  else
    echo "✅ Codex CLI config.toml validation passed"
  fi
  if ! python3 - <<'PYHOOK'
import hashlib
import json
from pathlib import Path

hooks = json.loads(Path("home/dot_codex/hooks.json").read_text())["hooks"]["PreToolUse"]
assert len(hooks) == 1, hooks
group = hooks[0]
expected = [
    "sha256:8863117dfc0f0ed890109dff2a9c7eaa3076dd94ed001602d3de33ef7517dbdc",
    "sha256:5be52eb577c8c54cec54e7635c1fb9ad3fa4166798f3652f0444a50a5fadf979",
]
actual = []
for handler in group["hooks"]:
    normalized = {
        "type": "command",
        "command": handler["command"],
        "timeout": max(int(handler.get("timeout", 600)), 1),
        "async": bool(handler.get("async", False)),
    }
    if handler.get("commandWindows") is not None:
        normalized["commandWindows"] = handler["commandWindows"]
    if handler.get("statusMessage") is not None:
        normalized["statusMessage"] = handler["statusMessage"]
    if handler.get("additionalContextLimit") is not None:
        normalized["additionalContextLimit"] = handler["additionalContextLimit"]
    identity = {
        "event_name": "pre_tool_use",
        "matcher": group.get("matcher"),
        "hooks": [normalized],
    }
    payload = json.dumps(identity, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode()
    actual.append("sha256:" + hashlib.sha256(payload).hexdigest())
assert actual == expected, (actual, expected)
PYHOOK
  then
    echo "❌ Codex managed hook trusted_hash fingerprints drifted from hooks.json"
    FAILED=1
  else
    echo "✅ Codex managed hook trusted_hash fingerprints match hooks.json"
  fi
  FILES_CHECKED=$((FILES_CHECKED + 1))
fi

# Renovate が chezmoi source state の mise config を対象にすること
if [ -f "renovate.json" ]; then
  echo "Validating Renovate mise manager file pattern..."
  if ! python3 - <<'PYRENOVATE'
import json
from pathlib import Path

config = json.loads(Path("renovate.json").read_text())
patterns = config.get("mise", {}).get("managerFilePatterns", [])
assert r'/^home/dot_config/mise/config\.toml$/' in patterns
PYRENOVATE
  then
    echo "❌ Renovate mise manager does not include chezmoi source config"
    FAILED=1
  else
    echo "✅ Renovate mise manager includes chezmoi source config"
  fi
  FILES_CHECKED=$((FILES_CHECKED + 1))
fi

# 検証対象のファイルが存在しない場合はエラー
if [ $FILES_CHECKED -eq 0 ]; then
  echo "❌ No AI agent configuration files found to validate"
  exit 1
fi

echo "✅ All $FILES_CHECKED AI agent configuration files validated"
exit $FAILED
