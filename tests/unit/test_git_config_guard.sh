#!/bin/bash
# git-config-guard フック(Claude / Codex)の判定コーパステスト

# コマンド文字列は意図的にシングルクォートで書く(展開させない)
# shellcheck disable=SC2016
set -euo pipefail

# BASH_ENV (~/.bash_env) が PATH を書き換えるため無効化する (test_hooks.sh と同じ理由)
unset BASH_ENV

echo "Testing git-config-guard command corpus..."

FAILED=0
DENY_REASON="git config writes are blocked by policy; ask the user to run this manually"
CLAUDE_HOOK="home/dot_claude/hooks/executable_git-config-guard.sh"
CODEX_HOOK="home/dot_codex/hooks/executable_git-config-guard.sh"
CLAUDE_LIB="home/dot_claude/hooks/git-config-guard-lib.sh"
CODEX_LIB="home/dot_codex/hooks/git-config-guard-lib.sh"

# 両ツリーは同一の解析ロジックを配備するため、内容が一致していること
if cmp -s "$CLAUDE_LIB" "$CODEX_LIB"; then
  echo "✅ git-config-guard-lib.sh is identical in the Claude and Codex trees"
else
  echo "❌ git-config-guard-lib.sh differs between the Claude and Codex trees"
  FAILED=1
fi

# 実行環境の HOME に依存しないよう固定する(コンテナのマウント判定が HOME を参照する)。
# 大きなコマンドは引数長の上限に当たるため --rawfile で渡す。
CMD_FILE=$(mktemp)
trap 'rm -f "$CMD_FILE"' EXIT
run_hook() {
  local hook="$1" cmd="$2" cwd="${3:-/tmp}"
  printf '%s' "$cmd" >"$CMD_FILE"
  jq -n --rawfile c "$CMD_FILE" --arg d "$cwd" '{cwd: $d, tool_input: {command: $c}}' | env HOME=/home/tester timeout 60 bash "$hook" 2>&1
}

# expect: allow は出力なし、deny は permissionDecision と理由が完全一致
check() {
  local expect="$1" cmd="$2" cwd="${3:-/tmp}" hook name out label
  label=${cmd:0:200}
  label=${label//[$'\n\t']/ }
  for hook in "$CLAUDE_HOOK" "$CODEX_HOOK"; do
    name=claude
    [[ "$hook" == "$CODEX_HOOK" ]] && name=codex
    out=$(run_hook "$hook" "$cmd" "$cwd") || {
      echo "❌ [$name] hook exited non-zero for: $label"
      FAILED=1
      continue
    }
    if [[ "$expect" == allow ]]; then
      if [[ -n "$out" ]]; then
        echo "❌ [$name] expected allow, got output for: $label"
        FAILED=1
      fi
    else
      if [[ "$(jq -r '.hookSpecificOutput.permissionDecision // empty' <<<"$out" 2>/dev/null)" != deny ||
        "$(jq -r '.hookSpecificOutput.permissionDecisionReason // empty' <<<"$out" 2>/dev/null)" != "$DENY_REASON" ]]; then
        echo "❌ [$name] expected deny, got '${out}' for: $label"
        FAILED=1
      fi
    fi
  done
}

# 生の JSON を渡す(\uXXXX エスケープなど、jq --arg では作れない入力用)
check_raw() {
  local expect="$1" json="$2" hook name out
  for hook in "$CLAUDE_HOOK" "$CODEX_HOOK"; do
    name=claude
    [[ "$hook" == "$CODEX_HOOK" ]] && name=codex
    out=$(printf '%s' "$json" | env HOME=/home/tester timeout 60 bash "$hook" 2>&1) || {
      echo "❌ [$name] hook exited non-zero for raw JSON: $json"
      FAILED=1
      continue
    }
    if [[ "$expect" == allow && -n "$out" ]]; then
      echo "❌ [$name] expected allow, got output for raw JSON: $json"
      FAILED=1
    elif [[ "$expect" == deny && "$(jq -r '.hookSpecificOutput.permissionDecision // empty' <<<"$out" 2>/dev/null)" != deny ]]; then
      echo "❌ [$name] expected deny, got '${out}' for raw JSON: $json"
      FAILED=1
    fi
  done
}

# 入力 JSON の cwd(<none> はキーなし)と、フックプロセスの PWD(home / other)を変えて判定する
ROOT=$PWD
FAKE_HOME=$(mktemp -d)
OTHER_DIR=$(mktemp -d)
mkdir "$FAKE_HOME/proj"
trap 'rm -f "$CMD_FILE"; rm -rf "$FAKE_HOME" "$OTHER_DIR"' EXIT
check_cwd() {
  local expect="$1" cmd="$2" cwdval="$3" pwdmode="$4" hook name out json dir="$OTHER_DIR"
  [[ "$pwdmode" == home ]] && dir="$FAKE_HOME"
  if [[ "$cwdval" == "<none>" ]]; then
    json=$(jq -nc --arg c "$cmd" '{tool_input: {command: $c}}')
  else
    json=$(jq -nc --arg c "$cmd" --arg d "$cwdval" '{cwd: $d, tool_input: {command: $c}}')
  fi
  for hook in "$CLAUDE_HOOK" "$CODEX_HOOK"; do
    name=claude
    [[ "$hook" == "$CODEX_HOOK" ]] && name=codex
    out=$(cd "$dir" && printf '%s' "$json" | env HOME="$FAKE_HOME" timeout 60 bash "$ROOT/$hook" 2>&1) || {
      echo "❌ [$name] hook exited non-zero (cwd=$cwdval pwd=$pwdmode): $cmd"
      FAILED=1
      continue
    }
    if [[ "$expect" == allow && -n "$out" ]]; then
      echo "❌ [$name] expected allow (cwd=$cwdval pwd=$pwdmode): $cmd"
      FAILED=1
    elif [[ "$expect" == deny && "$(jq -r '.hookSpecificOutput.permissionDecision // empty' <<<"$out" 2>/dev/null)" != deny ]]; then
      echo "❌ [$name] expected deny (cwd=$cwdval pwd=$pwdmode), got '${out}': $cmd"
      FAILED=1
    fi
  done
}

NL=$'\n'
TAB=$'\t'

# --- 許可: 読み取り ---
check allow 'git config user.name'
check allow 'git config --get user.name'
check allow 'git config --list'
check allow 'git config get user.name'
check allow 'git config list'
check allow 'git config --global user.name'
check allow 'git config --file .gitmodules --get submodule.x.path'
check allow 'git config --default x --get a.b'
check allow 'git -C /tmp/x config --get user.name'
check allow 'git -c core.pager=cat config --list'
check allow 'echo hi; git config user.name'
check allow 'if git config --get user.name; then echo y; fi'
check allow 'echo $(git config --get user.name)'
check allow 'git status'

# --- 許可: リダイレクトは位置引数に数えない ---
check allow 'git config user.name >/dev/null && echo ok'
check allow 'git config --get user.name 2>/dev/null'
check allow 'git config --get user.name 2>&1 | head -1'
check allow 'git config --get user.name &>/dev/null'
check allow 'git config user.name > out.txt'

# --- 許可: データとして現れるだけの文字列 ---
check allow 'echo "git config user.name Foo"'
check allow "printf '%s\\n' 'git config --global user.email a@b'"
check allow "grep -n 'git config user.name Foo' README.md"
check allow "sed -i 's/git config a b/x/' f.md"
check allow 'git commit -m "docs: explain git config user.name Foo"'
check allow 'echo a # git config a b'
check allow "cat > notes.md <<'EOF'${NL}use git config user.name Foo${NL}git config --global user.email x@y${NL}EOF"
check allow "cat > notes.md <<EOF${NL}use git config user.name Foo${NL}EOF"
check allow "cat > notes.md <<-EOF${NL}${TAB}git config user.name Foo${NL}${TAB}EOF"
check allow "cat <<\"EOF\" > f${NL}git config a b${NL}EOF${NL}git config --get user.name"
check allow "cat <<EOF${NL}\$(git config user.name)${NL}EOF"
check allow "bash -c 'echo git config a b'"

# --- 許可: コンテナ内に閉じた書き込み ---
check allow "docker run --rm ubuntu bash -c 'apt-get install -y git && git config --global safe.directory /work'"
check allow "docker run --rm -v \"\$PWD\":/work -w /work ubuntu bash -c 'git config --global --add safe.directory \"*\" && bash tests/x.sh'"
check allow 'docker run --rm -v /home/tester/.gitconfig:/root/.gitconfig:ro ubuntu git config --global a b'
check allow 'docker run --rm --mount type=bind,src=/home/tester,dst=/root,readonly ubuntu git config --global a b'
check allow 'podman run --rm -v data:/data ubuntu git config --global a b'

# --- 拒否: 書き込み ---
check deny 'git config foo.bar baz'
check deny 'git config user.name "Foo"'
check deny 'git config --global user.name X'
check deny 'git config --global user.email foo@example.com'
check deny 'git config --unset user.name'
check deny 'git config --edit'
check deny 'git config -e'
check deny 'git config --uns user.name'
check deny 'git config --add a b'
check deny 'git config --global --replace-all a b'
check deny 'git config --type bool a true'
check deny 'git config set user.name X'
check deny 'git config unset user.name'
check deny 'git config --list && git config user.name attacker'
check deny 'git config user.name attacker --get x'
check deny 'git config user.name attacker && echo git config'
check deny 'git config user.name X > /dev/null'
check deny 'git config --global user.name X 2>/dev/null'
check deny "echo a${NL}git config a b"

# --- 拒否: コマンド位置の変形 ---
check deny 'git  config user.name X'
check deny 'git -C /tmp/x config user.name X'
check deny 'git -c core.pager=cat config --global user.name X'
check deny '/usr/bin/git config a b'
check deny 'command git config a b'
check deny 'sudo -u bob git config a b'
check deny 'env FOO=1 git config a b'
check deny 'FOO=1 git config a b'
check deny 'time git config a b'
check deny '"git" config a b'
check deny 'g\it config a b'
check deny '$GIT config a b'
check deny '{ git config a b; }'
check deny '(git config a b)'
check deny 'if true; then git config a b; fi'
check deny 'true || git config a b'
check deny "find . -name x -exec git config a b \\;"
check deny "echo 'user.name X' | xargs git config"
check deny "watch -n1 'git config a b'"

# --- 拒否: 別のシェル・置換に包まれた書き込み ---
check deny "bash -c 'git config --global user.name X'"
check deny 'sh -c "git config a b"'
check deny "bash -lc 'git config a b'"
check deny "bash -c \"sh -c 'git config a b'\""
check deny 'eval "git config a b"'
check deny "echo x | xargs sh -c 'git config a b'"
check deny "echo 'git config a b' | bash"
check deny "bash <<'EOF'${NL}git config a b${NL}EOF"
check deny "cat <<EOF | sh${NL}git config a b${NL}EOF"
check deny "bash <<< 'git config a b'"
check deny 'echo "$(git config a b)"'
check deny 'echo `git config a b`'
check deny "cat <<EOF${NL}\$(git config a b)${NL}EOF"
check deny 'diff <(git config a b) x'
check deny "bash -c 'x=\$(git config a b)'"

# --- 作業ディレクトリが HOME のとき $PWD や . のマウントは HOME のマウントになる ---
check deny 'docker run --rm -v $PWD:/w ubuntu git config --global a b' /home/tester
check deny 'docker run --rm -v .:/w ubuntu git config --global a b' /home/tester
check deny 'docker run --rm -v "$(pwd)":/w ubuntu git config --global a b' /home/tester
check allow 'docker run --rm -v $PWD:/w ubuntu git config --global a b' /home/tester/proj
check allow 'docker run --rm -v .:/w ubuntu git config --global a b' /home/tester/proj
check allow 'docker run --rm -v ./sub:/w ubuntu git config --global a b' /home/tester
check allow 'docker run --rm --volume "$HOME" ubuntu git config --global a b'

# cwd が欠ける・空・相対のときはフックプロセスの PWD に戻る(PWD が HOME なら HOME のマウント)
for m in '-v $PWD:/w' '-v .:/w'; do
  c="docker run --rm $m ubuntu git config --global a b"
  check_cwd deny "$c" '<none>' home
  check_cwd deny "$c" '' home
  check_cwd deny "$c" proj home
  check_cwd deny "$c" "$FAKE_HOME" other
  check_cwd allow "$c" '<none>' other
  check_cwd allow "$c" '' other
  check_cwd allow "$c" proj other
  check_cwd allow "$c" "$OTHER_DIR" home
  check_cwd allow "$c" "$OTHER_DIR" other
done

# JSON の \uXXXX で綴った語は jq のデコード後に判定する(生の JSON への足切りをすり抜けない)
BS=$(printf '\134')
check_raw deny "{\"tool_input\":{\"command\":\"${BS}u0067${BS}u0069${BS}u0074 ${BS}u0063${BS}u006f${BS}u006e${BS}u0066${BS}u0069${BS}u0067 a b\"}}"
check_raw deny "{\"tool_input\":{\"command\":\"${BS}u0067it config a b\"}}"
check_raw deny "{\"tool_input\":{\"command\":\"git ${BS}u0063onfig a b\"}}"
check_raw deny "{\"tool_input\":{\"command\":\"bash -c 'git c${BS}u006fnfig --global a b'\"}}"
check_raw allow "{\"tool_input\":{\"command\":\"git ${BS}u0063onfig --get a.b\"}}"
check_raw allow "{\"tool_input\":{\"command\":\"${BS}u0067it status\"}}"

# --- 中身を静的に見られないもの(旧実装と同じく許可される設計上の限界) ---
check allow 'bash ./x.sh'
check allow 'source ./x.sh'

# --- 拒否: コンテナでもホストを書き換えうるもの ---
check deny 'docker run --rm -v /home/tester/.gitconfig:/root/.gitconfig ubuntu git config --global user.name X'
check deny 'docker run --rm -v "$HOME":/root ubuntu bash -c "git config --global a b"'
check deny 'docker run --rm -v ~/.config:/root/.config ubuntu git config --global a b'
check deny 'docker run --rm -v /:/host ubuntu git config --global a b'
check deny 'docker run --rm --mount type=bind,src=/home/tester/.config/git,dst=/root/.config/git ubuntu git config --global a b'
check deny 'docker run --rm --volumes-from c ubuntu git config --global a b'
check deny "docker run --rm -v \"\$PWD\":/work ubuntu bash -c 'git config user.name X'"
check deny 'docker run --rm -v "$PWD":/work ubuntu git config --local a b'
check deny 'docker run --rm -v "$PWD":/work ubuntu git config --file /work/x a b'
check deny 'docker exec c git config --global a b'
check deny "docker exec c bash -c 'git config --global a b'"
check deny 'kubectl exec pod -- git config --global a b'

# シェルの標準入力に流し込む形(旧実装は部分一致で拒否していた)
check deny "echo 'git config a b' | bash -"
check deny "echo 'git config a b' | bash -x -"
check deny 'printf "%s\n" "git config a b" | sh'
check deny "printf '%s' 'git config a b' | bash -"
check deny "echo -e 'git config a b' | bash"
check deny "echo -n 'git config a b' | bash"
check deny "echo 'git config a b' | (bash)"
check allow 'echo hi | bash -'
check allow "echo 'git config --get user.name' | bash -"

# コマンドを引数に取る未知のラッパー
check deny "env -S 'git config a b'"
check deny "env --split-string='git config a b'"
check deny 'flock /tmp/l git config a b'
check deny "flock -c 'git config a b' /tmp/l"
check deny 'taskset 1 git config a b'
check deny 'strace git config a b'
check deny "tmux new -d 'git config a b'"
check deny "script -qc 'git config a b' /dev/null"
check deny 'runuser -u x -- git config a b'
check deny "git -c 'alias.x=!git config a b' x"
check allow 'man git config'
check allow 'which git'
check allow "tmux send-keys 'echo hi' Enter"

# HOME のマウントを正規化されていないパスで書いても HOME として扱う
check deny 'docker run --rm -v /home/tester//:/root ubuntu git config --global a b'
check deny 'docker run --rm -v /home//tester:/root ubuntu git config --global a b'
check deny 'docker run --rm -v /home/./tester:/root ubuntu git config --global a b'
check deny 'docker run --rm -v /home/tester/.:/root ubuntu git config --global a b'
check deny 'docker run --rm --mount type=bind,source=/home/tester//,target=/root ubuntu git config --global a b'
check deny 'docker run --rm -v //:/host ubuntu git config --global a b'

# 解析が時間切れになる巨大な単語の後ろに書き込みを置いても素通しにならない
PAD=$(head -c 120000 /dev/zero | tr '\0' a)
for hook in "$CLAUDE_HOOK" "$CODEX_HOOK"; do
  out=$(run_hook "$hook" "echo config ${PAD}; git config a b") || out="exit $?"
  if [[ "$(jq -r '.hookSpecificOutput.permissionDecisionReason // empty' <<<"$out" 2>/dev/null)" != "git config analysis failed or timed out (exit 124); split the command or ask the user to run it manually" ]]; then
    echo "❌ $hook did not fail closed on a command that times out the analysis: ${out:0:200}"
    FAILED=1
  fi
done

# lib が配備されていなければ、書き込みの有無に関わらず config を含むコマンドは拒否する
MISSING_LIB_DIR=$(mktemp -d)
for hook in "$CLAUDE_HOOK" "$CODEX_HOOK"; do
  cp "$hook" "$MISSING_LIB_DIR/guard.sh"
  out=$(jq -n '{cwd: "/tmp", tool_input: {command: "git config a b"}}' | env HOME=/home/tester bash "$MISSING_LIB_DIR/guard.sh" 2>&1) || out="exit $?"
  if [[ "$(jq -r '.hookSpecificOutput.permissionDecisionReason // empty' <<<"$out" 2>/dev/null)" != "git-config-guard-lib.sh is missing next to git-config-guard.sh; run chezmoi apply" ]]; then
    echo "❌ $hook did not fail closed with a missing lib: $out"
    FAILED=1
  fi
done
rm -rf "$MISSING_LIB_DIR"

# 大きな heredoc でも一定時間内に判定が終わること(O(n^2) の回帰検知)
BIG=$(awk 'BEGIN { for (i = 0; i < 6000; i++) print "line " i " git config user.name Foo" }')
START=$SECONDS
check allow "cat > big.md <<'EOF'${NL}${BIG}${NL}EOF"
if ((SECONDS - START > 10)); then
  echo "❌ git-config-guard took $((SECONDS - START))s on a large heredoc"
  FAILED=1
fi

if [[ $FAILED -eq 0 ]]; then
  echo "✅ git-config-guard corpus passed for both hooks"
fi
exit $FAILED
