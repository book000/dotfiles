#!/bin/bash
# AI エージェント フックのユニットテスト

set -euo pipefail

# BASH_ENV (~/.bash_env) が mise の PATH を先頭に追加し、PATH 先頭に置いたスタブの gh / gitleaks が本物に隠れるため無効化する
unset BASH_ENV

echo "Testing AI agent hooks..."

FAILED=0

echo "Testing gh-pr-target-repo helper behavior..."
TEST_REPO_DIR=$(mktemp -d)
if ! (
  cd "$TEST_REPO_DIR" || exit 1
  git init -q
  git remote add upstream git@gitlab.com:example/not-github.git
  git remote add origin git@github.com:akubiusa/dotfiles.git
  HELPER_OUTPUT=$(bash "$OLDPWD/home/bin/executable_gh-pr-target-repo.sh")
  if [[ "$HELPER_OUTPUT" != "akubiusa/dotfiles" ]]; then
    echo "❌ gh-pr-target-repo helper did not ignore non-GitHub upstream remote"
    exit 1
  fi

  git remote set-url upstream git@github.com:book000/dotfiles.git
  HELPER_OUTPUT=$(bash "$OLDPWD/home/bin/executable_gh-pr-target-repo.sh")
  if [[ "$HELPER_OUTPUT" != "book000/dotfiles" ]]; then
    echo "❌ gh-pr-target-repo helper did not prefer GitHub upstream remote"
    exit 1
  fi
) ; then
  FAILED=1
else
  echo "✅ gh-pr-target-repo helper resolved GitHub remotes correctly"
fi
rm -rf "$TEST_REPO_DIR"

echo "Testing gh-pr-target-repo helper --origin behavior..."
TEST_REPO_DIR=$(mktemp -d)
if ! (
  cd "$TEST_REPO_DIR" || exit 1
  git init -q
  git remote add upstream git@github.com:book000/dotfiles.git
  git remote add origin git@github.com:akubiusa/dotfiles.git
  HELPER_OUTPUT=$(bash "$OLDPWD/home/bin/executable_gh-pr-target-repo.sh" --origin)
  if [[ "$HELPER_OUTPUT" != "akubiusa/dotfiles" ]]; then
    echo "❌ gh-pr-target-repo helper --origin did not resolve origin specifically"
    exit 1
  fi
) ; then
  FAILED=1
else
  echo "✅ gh-pr-target-repo helper --origin resolved origin regardless of upstream"
fi
rm -rf "$TEST_REPO_DIR"

echo "Testing gh-pr-target-repo helper fallback behavior..."
TEST_REPO_DIR=$(mktemp -d)
TEST_BIN_DIR=$(mktemp -d)
if ! (
  cd "$TEST_REPO_DIR" || exit 1
  git init -q
  cat > "$TEST_BIN_DIR/gh" <<'EOF'
#!/bin/bash
if [[ "$1" == "repo" && "$2" == "view" ]]; then
  echo "fallback-owner/fallback-repo"
  exit 0
fi
exit 1
EOF
  chmod +x "$TEST_BIN_DIR/gh"

  HELPER_OUTPUT=$(PATH="$TEST_BIN_DIR:$PATH" bash "$OLDPWD/home/bin/executable_gh-pr-target-repo.sh")
  if [[ "$HELPER_OUTPUT" != "fallback-owner/fallback-repo" ]]; then
    echo "❌ gh-pr-target-repo helper did not fall back to gh repo view"
    exit 1
  fi

  if PATH="$TEST_BIN_DIR:$PATH" bash "$OLDPWD/home/bin/executable_gh-pr-target-repo.sh" --remote >/dev/null 2>&1; then
    echo "❌ gh-pr-target-repo helper returned a synthetic remote name for gh fallback"
    exit 1
  fi
) ; then
  FAILED=1
else
  echo "✅ gh-pr-target-repo helper handled gh fallback without synthetic remote names"
fi
rm -rf "$TEST_REPO_DIR" "$TEST_BIN_DIR"

echo "Testing gh-pr-reviewer helper behavior..."
TEST_BIN_DIR=$(mktemp -d)
cat > "$TEST_BIN_DIR/gh" <<'EOF'
#!/bin/bash
if [[ "$1" == "api" && "$2" == "user" ]]; then
  [[ "${STUB_USER_FAIL:-0}" == "1" ]] && exit 1
  echo "${STUB_USER:-akubiusa}"
  exit 0
fi
if [[ "$1" == "api" && "$2" == "repos/book000/dotfiles/collaborators/book000" ]]; then
  exit "${STUB_COLLAB_EXIT:-0}"
fi
exit 1
EOF
chmod +x "$TEST_BIN_DIR/gh"
REVIEWER_HELPER="$PWD/home/bin/executable_gh-pr-reviewer.sh"

run_reviewer_helper() {
  local stderr_file
  stderr_file=$(mktemp)
  HELPER_EXIT=0
  HELPER_STDOUT=$(PATH="$TEST_BIN_DIR:$PATH" bash "$REVIEWER_HELPER" "$@" 2>"$stderr_file") || HELPER_EXIT=$?
  HELPER_STDERR=$(cat "$stderr_file")
  rm -f "$stderr_file"
}

assert_reviewer_helper() {
  local label="$1" want_exit="$2" want_stdout="$3" want_stderr="$4"
  if [[ "$HELPER_EXIT" != "$want_exit" || "$HELPER_STDOUT" != "$want_stdout" ]]; then
    echo "❌ gh-pr-reviewer helper: $label (exit=$HELPER_EXIT stdout=\"$HELPER_STDOUT\")"
    FAILED=1
  elif [[ "$want_stderr" == "empty" && -n "$HELPER_STDERR" ]] || [[ "$want_stderr" == "nonempty" && -z "$HELPER_STDERR" ]]; then
    echo "❌ gh-pr-reviewer helper: $label (unexpected stderr state: \"$HELPER_STDERR\")"
    FAILED=1
  else
    echo "✅ gh-pr-reviewer helper: $label"
  fi
}

STUB_USER=akubiusa STUB_COLLAB_EXIT=0 run_reviewer_helper book000/dotfiles
assert_reviewer_helper "requests book000 for another author" 0 "book000" empty

STUB_USER=book000 run_reviewer_helper book000/dotfiles
assert_reviewer_helper "skips when the author is book000" 0 "" empty

STUB_USER=akubiusa STUB_COLLAB_EXIT=1 run_reviewer_helper book000/dotfiles
assert_reviewer_helper "skips when book000 is not a collaborator" 0 "" nonempty

STUB_USER_FAIL=1 run_reviewer_helper book000/dotfiles
assert_reviewer_helper "fails when gh api user fails" 1 "" nonempty

run_reviewer_helper 'book000/dotfiles;rm'
assert_reviewer_helper "rejects a malformed repository" 1 "" nonempty

run_reviewer_helper
assert_reviewer_helper "rejects a missing repository" 1 "" nonempty
rm -rf "$TEST_BIN_DIR"

echo "Testing Codex Copilot wait script notification behavior..."
TEST_HOME=$(mktemp -d)
TEST_BIN_DIR=$(mktemp -d)
TEST_LOG_DIR="$TEST_HOME/.codex/logs"
TEST_LOCK_DIR="$TEST_HOME/.codex/locks"
TEST_CAPTURE_DIR=$(mktemp -d)
mkdir -p "$TEST_HOME/bin" "$TEST_HOME/.codex/scripts/completion-notify" "$TEST_LOG_DIR" "$TEST_LOCK_DIR"

cat > "$TEST_HOME/.env" <<EOF
SOURCE_COUNT_FILE="$TEST_CAPTURE_DIR/source-count"
echo sourced >> "\$SOURCE_COUNT_FILE"
DISCORD_CODEX_MENTION_USER_ID="1234567890"
EOF

cp home/bin/executable_gh-pr-target-repo.sh "$TEST_HOME/bin/gh-pr-target-repo.sh"
chmod +x "$TEST_HOME/bin/gh-pr-target-repo.sh"

cat > "$TEST_HOME/.codex/scripts/completion-notify/send-discord-notification.sh" <<'EOF'
#!/bin/bash
sleep 0.2
cat > "${TEST_CAPTURE_DIR}/discord-payload.json"
EOF
chmod +x "$TEST_HOME/.codex/scripts/completion-notify/send-discord-notification.sh"

cat > "$TEST_BIN_DIR/gh" <<'EOF'
#!/bin/bash
if [[ "$1" == "api" && "$2" == "graphql" ]]; then
  echo "1"
  exit 0
fi
exit 1
EOF
chmod +x "$TEST_BIN_DIR/gh"

cat > "$TEST_BIN_DIR/tmux" <<'EOF'
#!/bin/bash
if [[ "$1" == "display-message" && "$2" == "-p" ]]; then
  echo "test-session"
  exit 0
fi
if [[ "$1" == "send-keys" ]]; then
  printf '%s\n' "$*" >> "${TEST_CAPTURE_DIR}/tmux.log"
  exit 0
fi
exit 1
EOF
chmod +x "$TEST_BIN_DIR/tmux"

if ! (
  TEST_CAPTURE_DIR="$TEST_CAPTURE_DIR" PATH="$TEST_BIN_DIR:$PATH" HOME="$TEST_HOME" \
    bash home/dot_agents/skills/pr-health-monitor/scripts/executable_wait-for-copilot-review.sh \
    "https://github.com/book000/dotfiles/pull/121"
); then
  echo "❌ wait-for-copilot-review.sh failed on existing review notification path"
  FAILED=1
else
  if [[ "$(wc -l < "$TEST_CAPTURE_DIR/source-count" | tr -d ' ')" != "1" ]]; then
    echo "❌ wait-for-copilot-review.sh sourced ~/.env more than once"
    FAILED=1
  else
    echo "✅ wait-for-copilot-review.sh sourced ~/.env only once"
  fi

  PAYLOAD_FILE="$TEST_CAPTURE_DIR/discord-payload.json"
  for _ in {1..100}; do
    if grep -Fq '<@1234567890> Codex CLI Notification' "$PAYLOAD_FILE" 2>/dev/null; then
      break
    fi
    sleep 0.05
  done
  if ! grep -Fq '<@1234567890> Codex CLI Notification' "$PAYLOAD_FILE" 2>/dev/null; then
    echo "❌ wait-for-copilot-review.sh did not include the configured mention in Discord payload"
    FAILED=1
  else
    echo "✅ wait-for-copilot-review.sh included the configured mention in Discord payload"
  fi

  COPILOT_STATE="$TEST_HOME/.local/state/codex-pr-monitor/$(printf '%s' 'https://github.com/book000/dotfiles/pull/121' | sha256sum | awk '{print $1}').json"
  if ! jq -e '.events.copilot_review.status == "pending"' "$COPILOT_STATE" >/dev/null; then
    echo "❌ wait-for-copilot-review.sh did not record a durable Copilot event"
    FAILED=1
  else
    echo "✅ wait-for-copilot-review.sh recorded a durable Copilot event"
  fi

  if [ -f "$TEST_CAPTURE_DIR/tmux.log" ]; then
    echo "❌ wait-for-copilot-review.sh attempted a tmux action handoff"
    FAILED=1
  else
    echo "✅ wait-for-copilot-review.sh did not attempt a tmux action handoff"
  fi
fi
rm -rf "$TEST_HOME" "$TEST_BIN_DIR" "$TEST_CAPTURE_DIR"

echo "Testing pre-commit hook (gitleaks secret scan)..."
PRECOMMIT_HOOK="home/dot_config/git/hooks/executable_pre-commit"

if [ ! -f "$PRECOMMIT_HOOK" ]; then
  echo "❌ pre-commit hook not found: $PRECOMMIT_HOOK"
  FAILED=1
else
  # シナリオ 1: gitleaks が PATH に無い場合は fail-open (exit 0 かつ警告) となること
  TEST_REPO_DIR=$(mktemp -d)
  TEST_BIN_DIR=$(mktemp -d)
  if ! (
    cd "$TEST_REPO_DIR" || exit 1
    git init -q
    HOOK_OUTPUT=$(PATH="$TEST_BIN_DIR" "$(command -v bash)" "$OLDPWD/$PRECOMMIT_HOOK" 2>&1)
    HOOK_EXIT=$?
    if [[ $HOOK_EXIT -ne 0 ]]; then
      echo "❌ pre-commit hook did not fail-open when gitleaks is missing (exit $HOOK_EXIT)"
      exit 1
    fi
    if ! echo "$HOOK_OUTPUT" | grep -qi "gitleaks not found"; then
      echo "❌ pre-commit hook did not warn about missing gitleaks"
      exit 1
    fi
  ); then
    FAILED=1
  else
    echo "✅ pre-commit hook fails open when gitleaks is missing"
  fi
  rm -rf "$TEST_REPO_DIR" "$TEST_BIN_DIR"

  # シナリオ 2: gitleaks がシークレットを検知した場合は exit 1 でブロックすること
  TEST_REPO_DIR=$(mktemp -d)
  TEST_BIN_DIR=$(mktemp -d)
  cat > "$TEST_BIN_DIR/gitleaks" << 'EOF'
#!/bin/bash
echo "leaks found" >&2
exit 1
EOF
  chmod +x "$TEST_BIN_DIR/gitleaks"
  if ! (
    cd "$TEST_REPO_DIR" || exit 1
    git init -q
    if PATH="$TEST_BIN_DIR:$PATH" bash "$OLDPWD/$PRECOMMIT_HOOK" > /dev/null 2>&1; then
      echo "❌ pre-commit hook did not block commit when gitleaks detected a secret"
      exit 1
    fi
  ); then
    FAILED=1
  else
    echo "✅ pre-commit hook blocks commit when gitleaks detects a secret"
  fi
  rm -rf "$TEST_REPO_DIR" "$TEST_BIN_DIR"

  # シナリオ 3: リポジトリ側に .gitleaks.toml が無い場合はグローバル設定にフォールバックすること
  TEST_REPO_DIR=$(mktemp -d)
  TEST_BIN_DIR=$(mktemp -d)
  TEST_HOME=$(mktemp -d)
  TEST_ARGS_LOG=$(mktemp)
  cat > "$TEST_BIN_DIR/gitleaks" << EOF
#!/bin/bash
echo "\$*" > "$TEST_ARGS_LOG"
exit 0
EOF
  chmod +x "$TEST_BIN_DIR/gitleaks"
  echo "title = \"test\"" > "$TEST_HOME/.gitleaks.toml"
  if ! (
    cd "$TEST_REPO_DIR" || exit 1
    git init -q
    HOME="$TEST_HOME" PATH="$TEST_BIN_DIR:$PATH" bash "$OLDPWD/$PRECOMMIT_HOOK" > /dev/null 2>&1
    if ! grep -q -- "--config $TEST_HOME/.gitleaks.toml" "$TEST_ARGS_LOG"; then
      echo "❌ pre-commit hook did not fall back to the global gitleaks config"
      exit 1
    fi
    if ! grep -q -- "protect --staged --redact -v" "$TEST_ARGS_LOG"; then
      echo "❌ pre-commit hook did not pass protect --staged --redact -v to gitleaks"
      exit 1
    fi
  ); then
    FAILED=1
  else
    echo "✅ pre-commit hook falls back to the global gitleaks config when the repo has none"
  fi
  rm -rf "$TEST_REPO_DIR" "$TEST_BIN_DIR" "$TEST_HOME" "$TEST_ARGS_LOG"

  # シナリオ 4: リポジトリ側に .gitleaks.toml がある場合は --config を渡さず自動検出に任せること
  TEST_REPO_DIR=$(mktemp -d)
  TEST_BIN_DIR=$(mktemp -d)
  TEST_ARGS_LOG=$(mktemp)
  cat > "$TEST_BIN_DIR/gitleaks" << EOF
#!/bin/bash
echo "\$*" > "$TEST_ARGS_LOG"
exit 0
EOF
  chmod +x "$TEST_BIN_DIR/gitleaks"
  if ! (
    cd "$TEST_REPO_DIR" || exit 1
    git init -q
    echo 'title = "repo-local"' > .gitleaks.toml
    PATH="$TEST_BIN_DIR:$PATH" bash "$OLDPWD/$PRECOMMIT_HOOK" > /dev/null 2>&1
    if grep -q -- "--config" "$TEST_ARGS_LOG"; then
      echo "❌ pre-commit hook overrode the repo's own .gitleaks.toml"
      exit 1
    fi
  ); then
    FAILED=1
  else
    echo "✅ pre-commit hook defers to the repo's own .gitleaks.toml when present"
  fi
  rm -rf "$TEST_REPO_DIR" "$TEST_BIN_DIR" "$TEST_ARGS_LOG"

  # シナリオ 5: グローバルフォールバック設定 (home/dot_gitleaks.toml) が構文的に有効な TOML であること
  # (gitleaks は設定エラーとシークレット検知の両方で同じ終了コードを返すため、構文エラーが
  # 混入すると全リポジトリでコミットが無差別にブロックされる。real gitleaks は使わずに TOML
  # 構文のみを検証する)
  GITLEAKS_CONFIG="home/dot_gitleaks.toml"
  if ! python3 -c "import tomllib, sys; tomllib.load(open(sys.argv[1], 'rb'))" "$GITLEAKS_CONFIG"; then
    echo "❌ $GITLEAKS_CONFIG is not valid TOML"
    FAILED=1
  else
    echo "✅ $GITLEAKS_CONFIG is valid TOML"
  fi
fi

echo "Testing git-config-guard hook behavior..."
GIT_CONFIG_GUARD="home/dot_claude/hooks/executable_git-config-guard.sh"
CODEX_GIT_CONFIG_GUARD="home/dot_codex/hooks/executable_git-config-guard.sh"

run_git_config_guard() {
  local cmd="$1"
  jq -n --arg cmd "$cmd" '{"tool_input": {"command": $cmd}}' | bash "$GIT_CONFIG_GUARD"
}

# 読み取り系: 常に許可される(標準出力なし)
for cmd in \
  'git config --get user.name' \
  'git config --list' \
  'git config user.name' \
  'git status'; do
  OUTPUT=$(run_git_config_guard "$cmd")
  if [[ -n "$OUTPUT" ]]; then
    echo "❌ git-config-guard denied a command that should be allowed: $cmd"
    FAILED=1
  else
    echo "✅ git-config-guard allowed: $cmd"
  fi
done

echo "Testing Codex git-config-guard hook behavior..."
for cmd in \
  'git config --get user.name' \
  'git config user.name' \
  'git config user.name "Foo"' \
  'git config --global user.email foo@example.com'; do
  OUTPUT=$(jq -n --arg cmd "$cmd" '{tool_input: {command: $cmd}}' | bash "$CODEX_GIT_CONFIG_GUARD")
  DECISION=$(echo "$OUTPUT" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
  if [[ "$cmd" == *'"Foo"'* || "$cmd" == *'foo@example.com'* ]]; then
    if [[ "$DECISION" != "deny" ]]; then
      echo "❌ Codex git-config-guard did not deny: $cmd"
      FAILED=1
    fi
  elif [[ -n "$OUTPUT" ]]; then
    echo "❌ Codex git-config-guard denied: $cmd"
    FAILED=1
  fi
done

# hooks.json の matcher が "^(Bash|exec)$" に拡張されたため、tool_input が
# 文字列 (code-mode の "exec" tool) の PreToolUse でもクラッシュしないこと
# (jq の型エラーで rc!=0 にならないこと) を確認する。
EXEC_TOOL_INPUT_OUTPUT=$(jq -n '{tool_name: "exec", tool_input: "const r = await tools.exec_command({\"cmd\": \"git config --get user.name\"});"}' | bash "$CODEX_GIT_CONFIG_GUARD")
EXEC_TOOL_INPUT_RC=$?
if [[ "$EXEC_TOOL_INPUT_RC" -ne 0 ]]; then
  echo "❌ Codex git-config-guard crashed on non-object (exec) tool_input (rc=$EXEC_TOOL_INPUT_RC)"
  FAILED=1
elif [[ -n "$EXEC_TOOL_INPUT_OUTPUT" ]]; then
  echo "❌ Codex git-config-guard should pass through unparseable exec tool_input, got: $EXEC_TOOL_INPUT_OUTPUT"
  FAILED=1
else
  echo "✅ Codex git-config-guard passes through non-object (exec) tool_input without crashing"
fi

if ! jq empty home/dot_codex/hooks.json; then
  echo "❌ Codex hooks.json is invalid JSON"
  FAILED=1
elif ! jq -e '
  (.hooks.PreToolUse | length) == 1
  and .hooks.PreToolUse[0].matcher == "^(Bash|exec)$"
  and (.hooks.PreToolUse[0].hooks | length) == 1
  and .hooks.PreToolUse[0].hooks[0].command == "bash ~/.codex/hooks/git-config-guard.sh"
  and .hooks.PostToolUse[0].hooks[0].command == "bash ~/.codex/scripts/completion-notify/notify-post-tool-use.sh"
  and .hooks.PermissionRequest[0].hooks[0].command == "bash ~/.codex/hooks/pr-monitor-pane-state.sh approval_pending"
  and .hooks.UserPromptSubmit[0].hooks[0].command == "bash ~/.codex/hooks/pr-monitor-pane-state.sh busy"
  and .hooks.Stop[0].hooks[0].command == "bash ~/.codex/hooks/pr-monitor-pane-state.sh ready"
' home/dot_codex/hooks.json >/dev/null; then
  echo "❌ Codex hooks.json does not register the expected lifecycle hooks"
  FAILED=1
else
  echo "✅ Codex hooks.json registers the expected lifecycle hooks"
fi

# 書き込み系: permissionDecision: deny が出力される
# (回避策として、読み取りコマンドとの連結や、書き込みコマンドへの
# 読み取り系オプション付与によるすり抜けを試みるケースも含む)
for cmd in \
  'git config user.name "Foo"' \
  'git config --global user.email foo@example.com' \
  'git config --unset user.name' \
  'git config --list && git config user.name attacker' \
  'git config user.name attacker --get x' \
  'git config user.name attacker && echo git config'; do
  OUTPUT=$(run_git_config_guard "$cmd")
  DECISION=$(echo "$OUTPUT" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
  if [[ "$DECISION" != "deny" ]]; then
    echo "❌ git-config-guard did not deny a write command: $cmd"
    FAILED=1
  else
    echo "✅ git-config-guard denied: $cmd"
  fi
done

# JSON の \uXXXX エスケープで綴った語は、生の JSON には "git config" として現れない。
# 足切りをすり抜けず、jq のデコード後に判定されること(Claude / Codex 両方)。
BS=$(printf '\134')
GCG_DENY_REASON="git config writes are blocked by policy; ask the user to run this manually"
for hook in "$GIT_CONFIG_GUARD" "$CODEX_GIT_CONFIG_GUARD"; do
  for escaped in \
    "${BS}u0067${BS}u0069${BS}u0074 ${BS}u0063${BS}u006f${BS}u006e${BS}u0066${BS}u0069${BS}u0067 a b" \
    "${BS}u0067it config a b" \
    "git ${BS}u0063onfig a b" \
    "bash -c 'git c${BS}u006fnfig --global a b'"; do
    OUTPUT=$(printf '%s' "{\"tool_input\":{\"command\":\"$escaped\"}}" | bash "$hook")
    if [[ "$(echo "$OUTPUT" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)" != "deny" ||
      "$(echo "$OUTPUT" | jq -r '.hookSpecificOutput.permissionDecisionReason // empty' 2>/dev/null)" != "$GCG_DENY_REASON" ]]; then
      echo "❌ $hook did not deny an escaped write: $escaped"
      FAILED=1
    else
      echo "✅ $hook denied an escaped write: $escaped"
    fi
  done
  # \u を含んでいても無関係なコマンドは許可される(標準出力なし)
  for escaped in "${BS}u0067it status" "echo h${BS}u0065llo"; do
    OUTPUT=$(printf '%s' "{\"tool_input\":{\"command\":\"$escaped\"}}" | bash "$hook")
    if [[ -n "$OUTPUT" ]]; then
      echo "❌ $hook denied an unrelated escaped command: $escaped"
      FAILED=1
    else
      echo "✅ $hook allowed an unrelated escaped command: $escaped"
    fi
  done
done

echo "Testing detect-leaked-toolcall hook behavior..."
DETECT_LEAKED_TOOLCALL="home/dot_claude/hooks/executable_detect-leaked-toolcall.sh"

run_detect_leaked_toolcall() {
  local transcript_path="$1"
  local session_id="$2"
  jq -n --arg sid "$session_id" --arg tp "$transcript_path" '{"session_id": $sid, "transcript_path": $tp}' \
    | HOME="$TEST_HOOK_HOME" bash "$DETECT_LEAKED_TOOLCALL"
}

TEST_HOOK_HOME=$(mktemp -d)

# シナリオ 1: 最終アシスタントメッセージにツールコールのマークアップが漏れている場合はブロックすること
TEST_TRANSCRIPT=$(mktemp)
cat > "$TEST_TRANSCRIPT" <<'EOF'
{"type":"assistant","message":{"content":[{"type":"text","text":"続けます。<invoke name=\"Write\">"}]}}
EOF
OUTPUT=$(run_detect_leaked_toolcall "$TEST_TRANSCRIPT" "test-session-leak")
DECISION=$(echo "$OUTPUT" | jq -r '.decision // empty' 2>/dev/null)
if [[ "$DECISION" != "block" ]]; then
  echo "❌ detect-leaked-toolcall did not block a message with leaked tool-call markup"
  FAILED=1
else
  echo "✅ detect-leaked-toolcall blocked a message with leaked tool-call markup"
fi
rm -f "$TEST_TRANSCRIPT"

# シナリオ 2: 最終アシスタントメッセージが通常のプロースの場合はブロックしないこと
TEST_TRANSCRIPT=$(mktemp)
cat > "$TEST_TRANSCRIPT" <<'EOF'
{"type":"assistant","message":{"content":[{"type":"text","text":"ordinary prose without any tool-call markup."}]}}
EOF
OUTPUT=$(run_detect_leaked_toolcall "$TEST_TRANSCRIPT" "test-session-clean")
if [[ -n "$OUTPUT" ]]; then
  echo "❌ detect-leaked-toolcall produced output for an ordinary message: $OUTPUT"
  FAILED=1
else
  echo "✅ detect-leaked-toolcall stayed silent for an ordinary message"
fi
rm -f "$TEST_TRANSCRIPT"

# シナリオ 3: transcript_path が存在しない場合はブロックしないこと
OUTPUT=$(run_detect_leaked_toolcall "/nonexistent/path/transcript.jsonl" "test-session-missing")
if [[ -n "$OUTPUT" ]]; then
  echo "❌ detect-leaked-toolcall produced output for a missing transcript_path: $OUTPUT"
  FAILED=1
else
  echo "✅ detect-leaked-toolcall stayed silent for a missing transcript_path"
fi

rm -rf "$TEST_HOOK_HOME"

echo "Testing rtk-rewrite hook worktree bypass behavior..."
RTK_REWRITE_HOOK="home/dot_claude/hooks/executable_rtk-rewrite.sh"
RTK_FAKE_BIN_DIR=$(mktemp -d)

# jq --version は使わず rtk のみ差し替える。実際の rtk rewrite が観測した
# 変換パターン (git/ls トークンの直前にだけ「rtk 」を挿入し、演算子や他の
# 引数はそのまま) を sed の単語境界 (\<...\>) で模擬する。これにより
# `echo x && git status` のような compound command 内に埋め込まれた git も
# 検出でき、先頭アンカー方式の正規表現では拾えなかったケースを再現できる。
# ただし単純な単語境界 sed はクォート文字列の中身も区別なく書き換えて
# しまうため、クォート内にたまたま `rtk git` を含む 2 ケースだけは
# 実際の rtk (クォート内は書き換えない) の挙動に忠実な出力を直接指定する。
# コマンド文字列に DENYME / ASKME を含めることで、rtk 本体の
# deny (exit 2) / ask (exit 3 + stdout) 判定も模擬する。
cat > "$RTK_FAKE_BIN_DIR/rtk" <<'EOF'
#!/bin/bash
if [[ "$1" == "--version" ]]; then
  echo "rtk 0.43.0"
  exit 0
fi
if [[ "$1" == "rewrite" ]]; then
  CMD="$2"
  case "$CMD" in
    *DENYME*)
      exit 2
      ;;
  esac
  case "$CMD" in
    'ls && echo "rtk git status"')
      REWRITTEN='rtk ls && echo "rtk git status"'
      ;;
    'echo "rtk git status" && git status')
      REWRITTEN='echo "rtk git status" && rtk git status'
      ;;
    *)
      REWRITTEN=$(printf '%s' "$CMD" | sed -E 's/\<git\>/rtk git/g; s/\<ls\>/rtk ls/g')
      ;;
  esac
  echo "$REWRITTEN"
  case "$CMD" in
    *ASKME*)
      exit 3
      ;;
    *)
      exit 0
      ;;
  esac
fi
exit 1
EOF
chmod +x "$RTK_FAKE_BIN_DIR/rtk"

run_rtk_rewrite() {
  local cmd="$1"
  local cwd="$2"
  jq -n --arg cmd "$cmd" --arg cwd "$cwd" '{"cwd": $cwd, "tool_input": {"command": $cmd}}' \
    | PATH="$RTK_FAKE_BIN_DIR:$PATH" bash "$RTK_REWRITE_HOOK"
}

assert_rtk_rewritten() {
  local label="$1" cmd="$2" cwd="$3" expected_cmd="$4"
  local output adopted
  output=$(run_rtk_rewrite "$cmd" "$cwd")
  adopted=$(echo "$output" | jq -r '.hookSpecificOutput.updatedInput.command // empty' 2>/dev/null)
  if [[ "$adopted" != "$expected_cmd" ]]; then
    echo "❌ $label: expected RTK rewrite '$expected_cmd', got: $output"
    FAILED=1
  else
    echo "✅ $label"
  fi
}

assert_rtk_bypassed() {
  local label="$1" cmd="$2" cwd="$3"
  local output
  output=$(run_rtk_rewrite "$cmd" "$cwd")
  if [[ -n "$output" ]]; then
    echo "❌ $label: expected command to stay plain (no rtk rewrite), got: $output"
    FAILED=1
  else
    echo "✅ $label"
  fi
}

# deny 判定 (rtk rewrite exit 2) は元々このフック自身が何も出力せず、
# Claude Code 側のネイティブ deny ルールに委ねる設計のため、
# worktree 内外を問わず「出力なし」であることだけを確認すればよい。
assert_rtk_denied() {
  local label="$1" cmd="$2" cwd="$3"
  local output
  output=$(run_rtk_rewrite "$cmd" "$cwd")
  if [[ -n "$output" ]]; then
    echo "❌ $label: expected deny rule to pass through silently, got: $output"
    FAILED=1
  else
    echo "✅ $label"
  fi
}

# ask 判定 (rtk rewrite exit 3) は permissionDecision を出さずに
# ユーザー確認を求める点を維持しつつ、採用コマンドだけを
# 呼び出し側が指定した expected_cmd と比較する。
assert_rtk_asked() {
  local label="$1" cmd="$2" cwd="$3" expected_cmd="$4"
  local output decision adopted
  output=$(run_rtk_rewrite "$cmd" "$cwd")
  decision=$(echo "$output" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
  adopted=$(echo "$output" | jq -r '.hookSpecificOutput.updatedInput.command // empty' 2>/dev/null)
  if [[ -n "$decision" ]]; then
    echo "❌ $label: expected ask (no auto permissionDecision), got decision=$decision"
    FAILED=1
  elif [[ "$adopted" != "$expected_cmd" ]]; then
    echo "❌ $label: expected adopted command '$expected_cmd', got '$adopted'"
    FAILED=1
  else
    echo "✅ $label"
  fi
}

NORMAL_CWD="/home/user/project"
WORKTREE_CWD="/home/user/project/.claude/worktrees/issue-357"
RTK_DENY_CMD="git push --force DENYME"
RTK_ASK_CMD="git reset --hard ASKME"

assert_rtk_rewritten "normal cwd: git branch --show-current is still RTK-rewritten" \
  "git branch --show-current" "$NORMAL_CWD" "rtk git branch --show-current"
assert_rtk_bypassed "worktree cwd: git branch --show-current stays plain git" \
  "git branch --show-current" "$WORKTREE_CWD"
assert_rtk_bypassed "worktree cwd: git status --porcelain stays plain git" \
  "git status --porcelain" "$WORKTREE_CWD"
assert_rtk_rewritten "worktree cwd: non-git command ls -la is still RTK-rewritten" \
  "ls -la" "$WORKTREE_CWD" "rtk ls -la"
assert_rtk_bypassed "worktree cwd: 'command git status' stays plain git" \
  "command git status" "$WORKTREE_CWD"
assert_rtk_bypassed "worktree cwd: 'cd /some/path && git status' stays plain git" \
  "cd /some/path && git status" "$WORKTREE_CWD"
assert_rtk_rewritten "normal cwd: non-git command ls -la is still RTK-rewritten (regression)" \
  "ls -la" "$NORMAL_CWD" "rtk ls -la"

# 先頭アンカー方式の正規表現では検出できなかった、compound command 内に
# 埋め込まれた git (`&&`/`;` の後ろ) も、git launcher の新規導入を検出
# できれば漏れなく素通しできることを確認する。
assert_rtk_bypassed "worktree cwd: 'echo x && git status' (compound, &&) stays fully plain" \
  "echo x && git status" "$WORKTREE_CWD"
assert_rtk_rewritten "normal cwd: 'echo x && git status' (compound, &&) is still RTK-rewritten (regression)" \
  "echo x && git status" "$NORMAL_CWD" "echo x && rtk git status"
assert_rtk_asked "worktree cwd: 'pwd; git status ASKME' (compound, ;) still prompts but keeps plain git" \
  "pwd; git status ASKME" "$WORKTREE_CWD" "pwd; git status ASKME"

# git launcher が新規導入された compound command は、他の rewrite (rtk ls)
# を犠牲にしてでもコマンド全体を元に戻す (部分置換はしない、安全側優先)。
assert_rtk_bypassed "worktree cwd: 'ls && git status' reverts the whole command, sacrificing the rtk ls optimization" \
  "ls && git status" "$WORKTREE_CWD"
assert_rtk_rewritten "normal cwd: 'ls && git status' is still fully RTK-rewritten (regression)" \
  "ls && git status" "$NORMAL_CWD" "rtk ls && rtk git status"

# クォート文字列リテラルに偶然 `rtk git` という文字列が含まれるケースでは、
# 出現回数がリテラル分と一致するだけで増えないため、rewrite をそのまま
# 採用してよい (git 呼び出し自体が無いので、クォートも他の rewrite も
# 書き換えられてはならない)。
assert_rtk_rewritten "worktree cwd: 'ls && echo \"rtk git status\"' preserves the quoted literal and keeps the ls rewrite (no real git call)" \
  'ls && echo "rtk git status"' "$WORKTREE_CWD" 'rtk ls && echo "rtk git status"'
assert_rtk_rewritten "normal cwd: 'ls && echo \"rtk git status\"' is still RTK-rewritten (regression)" \
  'ls && echo "rtk git status"' "$NORMAL_CWD" 'rtk ls && echo "rtk git status"'

# 引用符内に既存の `rtk git` を含みつつ、末尾で実際に git launcher が
# 新規導入される場合は、出現回数が増えるため全体を巻き戻す。
assert_rtk_bypassed "worktree cwd: 'echo \"rtk git status\" && git status' reverts the whole command (real git launcher newly introduced)" \
  'echo "rtk git status" && git status' "$WORKTREE_CWD"
assert_rtk_rewritten "normal cwd: 'echo \"rtk git status\" && git status' is still RTK-rewritten (regression)" \
  'echo "rtk git status" && git status' "$NORMAL_CWD" 'echo "rtk git status" && rtk git status'

# worktree 内では、glob / 変数展開 / %{ トークン / クォート文字列を引数に持つ
# rtk launcher も巻き戻す。通常 cwd と、引数が平易な launcher は対象外。
assert_rtk_bypassed "worktree cwd: 'ls dir/*' (glob *) is reverted" \
  'ls dir/*' "$WORKTREE_CWD"
assert_rtk_bypassed "worktree cwd: 'ls dir/?.md' (glob ?) is reverted" \
  'ls dir/?.md' "$WORKTREE_CWD"
# shellcheck disable=SC2016
assert_rtk_bypassed "worktree cwd: 'ls \$HOME' (variable) is reverted" \
  'ls $HOME' "$WORKTREE_CWD"
# shellcheck disable=SC2016
assert_rtk_bypassed "worktree cwd: 'ls \$(pwd)' (command expansion) is reverted" \
  'ls $(pwd)' "$WORKTREE_CWD"
assert_rtk_bypassed "worktree cwd: 'ls \"my dir\"' (quoted text) is reverted" \
  'ls "my dir"' "$WORKTREE_CWD"
assert_rtk_bypassed "worktree cwd: 'ls -w %{x}' (%{ token) is reverted" \
  'ls -w %{x}' "$WORKTREE_CWD"
assert_rtk_bypassed "worktree cwd: 'echo x && ls *' (launcher in compound) reverts the whole command" \
  'echo x && ls *' "$WORKTREE_CWD"
assert_rtk_asked "worktree cwd: 'ls * ASKME' still prompts but keeps the original command" \
  'ls * ASKME' "$WORKTREE_CWD" 'ls * ASKME'
assert_rtk_denied "worktree cwd: deny-matched glob command still passes through silently" \
  'ls * DENYME' "$WORKTREE_CWD"
assert_rtk_rewritten "worktree cwd: 'ls -la && echo \"a b\"' keeps the rewrite (quote is outside the launcher)" \
  'ls -la && echo "a b"' "$WORKTREE_CWD" 'rtk ls -la && echo "a b"'
assert_rtk_rewritten "normal cwd: 'ls dir/*' is still RTK-rewritten" \
  'ls dir/*' "$NORMAL_CWD" 'rtk ls dir/*'
# shellcheck disable=SC2016
assert_rtk_rewritten "normal cwd: 'ls \$HOME' is still RTK-rewritten" \
  'ls $HOME' "$NORMAL_CWD" 'rtk ls $HOME'
assert_rtk_rewritten "normal cwd: 'ls \"my dir\"' is still RTK-rewritten" \
  'ls "my dir"' "$NORMAL_CWD" 'rtk ls "my dir"'
assert_rtk_rewritten "normal cwd: 'ls -w %{x}' is still RTK-rewritten" \
  'ls -w %{x}' "$NORMAL_CWD" 'rtk ls -w %{x}'

# deny/ask 判定は worktree 内の git であっても失われてはならない
# (rewrite だけをスキップし、safety net は維持する)。
assert_rtk_denied "normal cwd: deny-matched git command passes through silently" \
  "$RTK_DENY_CMD" "$NORMAL_CWD"
assert_rtk_denied "worktree cwd: deny-matched git command still passes through silently (deny preserved)" \
  "$RTK_DENY_CMD" "$WORKTREE_CWD"
assert_rtk_asked "normal cwd: ask-matched git command still prompts with the RTK-rewritten command" \
  "$RTK_ASK_CMD" "$NORMAL_CWD" "rtk git reset --hard ASKME"
assert_rtk_asked "worktree cwd: ask-matched git command still prompts but keeps plain git (ask preserved, no rtk rewrite)" \
  "$RTK_ASK_CMD" "$WORKTREE_CWD" "$RTK_ASK_CMD"

rm -rf "$RTK_FAKE_BIN_DIR"

echo "Testing deep-review / lite-review hooks..."
DR_HOME=$(mktemp -d)
DR_IMMEDIATE="$PWD/home/dot_claude/hooks/executable_deep-review-immediate-fix.sh"
DR_STOP="$PWD/home/dot_claude/hooks/executable_deep-review-require-fixes.sh"
DR_LEDGER="$PWD/home/dot_agents/skills/deep-review/scripts/executable_ledger.sh"
DR_DATA="$DR_HOME/.claude/data"

dr_ledger() { DEEP_REVIEW_DATA_DIR="$DR_DATA" bash "$DR_LEDGER" "$@"; }
dr_finding() {
  jq -nc --arg k "$1" '{key: $k, path: "a.kt", line: 1, reviewer: "b", title: "t", class: "merge-blocker", confidence: 90, verified: true}'
}
dr_immediate_input() {
  jq -nc --arg s "$1" --arg sk "$2" --arg r "${3:-}" \
    '{tool_name: "Skill", tool_input: {skill: $sk}, session_id: $s, tool_response: $r}'
}
# 引数: 期待 (block / pass)、説明、フック、入力 JSON
assert_dr_hook() {
  local expect="$1" msg="$2" hook="$3" input="$4" out
  out=$(HOME="$DR_HOME" bash "$hook" <<<"$input" 2>"$DR_HOME/stderr.${hook##*/}") || true
  if [[ "$expect" == "block" ]] && jq -e '.decision == "block"' <<<"$out" >/dev/null 2>&1; then
    echo "✅ $msg"
  elif [[ "$expect" == "pass" ]] && ! jq -e '.decision == "block"' <<<"$out" >/dev/null 2>&1; then
    echo "✅ $msg"
  else
    echo "❌ $msg (expected $expect, got: $out)"
    FAILED=1
  fi
}
# immediate-fix (PostToolUse) と require-fixes (Stop) の両方に同じ期待を適用する
assert_dr_both() {
  local expect="$1" msg="$2" sid="$3"
  assert_dr_hook "$expect" "immediate-fix: $msg" "$DR_IMMEDIATE" "$(dr_immediate_input "$sid" deep-review)"
  assert_dr_hook "$expect" "require-fixes: $msg" "$DR_STOP" "$(jq -nc --arg s "$sid" '{session_id: $s}')"
}

dr_ledger init s-review review pr o/r 1 true abc >/dev/null
dr_ledger add s-review "$(dr_finding k1)" >/dev/null
assert_dr_both pass "review-mode ledger with open blocker does not block" s-review

dr_ledger init s-fix fix pr o/r 1 true abc >/dev/null
dr_ledger add s-fix "$(dr_finding k1)" >/dev/null
assert_dr_both block "fix-mode ledger with open blocker blocks" s-fix
dr_ledger set-status s-fix 1 fixed abc verified >/dev/null
assert_dr_both pass "fix-mode ledger with all resolved does not block" s-fix

assert_dr_both pass "no ledger does not block" s-none

dr_ledger init s-mismatch fix pr o/r 1 true abc >/dev/null
dr_ledger add s-mismatch "$(dr_finding k1)" >/dev/null
jq '.session_id = "other"' "$DR_DATA/deep-review-ledger-s-mismatch.json" > "$DR_DATA/tmp.json" \
  && mv "$DR_DATA/tmp.json" "$DR_DATA/deep-review-ledger-s-mismatch.json"
assert_dr_both pass "session_id mismatch does not block" s-mismatch

dr_ledger init s-schema fix pr o/r 1 true abc >/dev/null
dr_ledger add s-schema "$(dr_finding k1)" >/dev/null
jq '.schema_version = 2' "$DR_DATA/deep-review-ledger-s-schema.json" > "$DR_DATA/tmp.json" \
  && mv "$DR_DATA/tmp.json" "$DR_DATA/deep-review-ledger-s-schema.json"
assert_dr_both pass "schema_version 2 does not block" s-schema

dr_ledger init s-stale fix pr o/r 1 true abc >/dev/null
dr_ledger add s-stale "$(dr_finding k1)" >/dev/null
jq '.updated_at = 0' "$DR_DATA/deep-review-ledger-s-stale.json" > "$DR_DATA/tmp.json" \
  && mv "$DR_DATA/tmp.json" "$DR_DATA/deep-review-ledger-s-stale.json"
assert_dr_both pass "ledger older than 24h does not block" s-stale

printf '{broken' > "$DR_DATA/deep-review-ledger-s-corrupt.json"
assert_dr_both pass "corrupted ledger does not block" s-corrupt
for hook in "$DR_IMMEDIATE" "$DR_STOP"; do
  if grep -q 'WARNING: corrupted deep-review ledger' "$DR_HOME/stderr.${hook##*/}"; then
    echo "✅ ${hook##*/}: corrupted ledger warns on stderr"
  else
    echo "❌ ${hook##*/}: corrupted ledger did not warn on stderr"
    FAILED=1
  fi
done

assert_dr_hook pass "deep-review with only 'Score: 90' in tool_response does not block" \
  "$DR_IMMEDIATE" "$(dr_immediate_input s-score deep-review 'Score: 90')"

# lite-review も deep-review と同じ ledger で判定する
assert_dr_hook pass "lite-review with only 'Score: 90' in tool_response does not block" \
  "$DR_IMMEDIATE" "$(dr_immediate_input s-lite-score lite-review 'Score: 90')"
dr_ledger init s-lite fix pr o/r 1 true abc >/dev/null
dr_ledger add s-lite "$(dr_finding k1)" >/dev/null
assert_dr_hook block "lite-review immediate-fix blocks on fix-mode ledger with open blocker" \
  "$DR_IMMEDIATE" "$(dr_immediate_input s-lite lite-review)"
assert_dr_hook block "lite-review Stop blocks on fix-mode ledger with open blocker" \
  "$DR_STOP" '{"session_id":"s-lite"}'
# Stop フックは動作中のバックグラウンドサブエージェントがある間だけブロックを見送る (monitor は対象外)
assert_dr_hook pass "Stop hook defers while a background subagent is running" \
  "$DR_STOP" '{"session_id":"s-lite","background_tasks":[{"type":"subagent","status":"running"}]}'
assert_dr_hook block "Stop hook still blocks when only a monitor is running" \
  "$DR_STOP" '{"session_id":"s-lite","background_tasks":[{"type":"monitor"},{"type":"shell"}]}'
assert_dr_hook block "Stop hook still blocks with empty background_tasks" \
  "$DR_STOP" '{"session_id":"s-lite","background_tasks":[]}'
dr_ledger set-status s-lite 1 fixed abc verified >/dev/null
assert_dr_hook pass "lite-review immediate-fix does not block after blocker is resolved" \
  "$DR_IMMEDIATE" "$(dr_immediate_input s-lite lite-review)"
assert_dr_hook pass "lite-review Stop does not block after blocker is resolved" \
  "$DR_STOP" '{"session_id":"s-lite"}'

# 解決済みの fix-mode ledger と残存した旧 state (high_score_count > 0) が併存してもブロックしない
dr_ledger init s-legacy fix pr o/r 1 true abc >/dev/null
jq -nc --argjson t "$(date +%s)" '{session_id: "s-legacy", skill: "lite-review", timestamp: $t, high_score_count: 1, max_score: 90}' \
  > "$DR_DATA/deep-review-state-s-legacy.json"
assert_dr_both pass "resolved fix-mode ledger with leftover legacy state does not block" s-legacy

rm -rf "$DR_HOME"

if [ $FAILED -eq 0 ]; then
  echo "✅ All hook tests passed"
else
  echo "❌ Some hook tests failed"
  exit 1
fi
