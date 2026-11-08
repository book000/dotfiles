## Purpose

This document describes the working policy for Claude Code and the rules specific to this repository.

@AGENTS.md

## Project Overview

- Purpose: manage dotfiles and AI agent settings with chezmoi.
- Main features: templating of shell settings, tmux settings, notification settings, and agent settings.

## Development Commands

- There is no `package.json`. There is no build step; deploy with `chezmoi apply`.
- For local verification, run `chezmoi apply` in Docker and check the result.
- Run the tests by executing the shell scripts under `tests/` directly (see "Testing" below).

## Architecture and Key Files

- `home/`: chezmoi source.
- `home/dot_*`: actual dotfiles, expressed with the `dot_` prefix.
- `home/dot_*/*.tmpl`: template files.
- `home/dot_*/*.d`: split placement of additional settings.

## chezmoi File Naming Rules

chezmoi interprets source-side prefixes when deploying. Main prefixes:

| Source file name | Deployed file name | Notes |
|---|---|---|
| `executable_foo.sh` | `foo.sh` (executable) | `executable_` is removed |
| `dot_foo` | `.foo` | `dot_` is converted to `.` |
| `symlink_foo` | `foo` (symbolic link) | The link target is the file content |

**Important**: The `executable_` prefix is removed at deploy time. Therefore, in configuration files that invoke scripts from outside (such as `settings.json`), write paths without `executable_`.

```jsonc
// Correct
{"command": "bash ~/.claude/hooks/foo.sh"}

// Wrong (the file does not exist after chezmoi apply)
{"command": "bash ~/.claude/hooks/executable_foo.sh"}
```

Do not use the `symlink_executable_` pattern (a workaround that creates an `executable_`-prefixed name via a symbolic link).

## Implementation Patterns

Recommended:
- Split shell settings into `.d` directories.

Discouraged:
- Committing secrets in plain text.
- Appending everything to one huge configuration file.

## Coding Conventions

- Language: Bash / Zsh.
- Follow Conventional Commits for commit messages.
- Match the structure and naming patterns of existing files.

## Testing

- Shell script tests live under `tests/` and fall into the following 3 groups:
  - `tests/syntax/`: `test_bash_syntax.sh` / `test_shellcheck.sh` / `test_json_schema.sh` (syntax, shellcheck, JSON schema). The shell syntax and shellcheck tests skip `.claude/worktrees/` and `.worktrees/`.
  - `tests/unit/`: `test_install.sh` / `test_update.sh` / `test_notifications.sh` / `test_hooks.sh` / `test_deep_review_ledger.sh` / `test_deep_review_comment.sh` / `test_deep_review_layout.sh` / `test_measure_usage.sh` / `test_list_compose_dirs.sh` / `test_language_policy.sh` / `test_pr_watch_events.sh` / `test_rtk_hook_hash.sh` / `test_write_session_state.sh` / `test_review_thread_hook.sh` / `test_git_config_guard.sh` (command corpus for the git config guard hooks of both Claude and Codex).
  - `tests/integration/`: `test_chezmoi_apply.sh` (integration test for `chezmoi apply`) / `test_gitleaks.sh` (regression test against a pinned real gitleaks binary) / `test_mise_tools.sh` (mise CLI smoke test) / `test_pr_monitor_tmux.sh` (real tmux delayed-Enter test; CI installs tmux first because the test skips without it).
- CI runs automatically on pull_request via `unit-test.yml` / `integration-test.yml` / `pr-checks.yml` under `.github/workflows/` (`unit-test.yml` / `integration-test.yml` also run on push to master).
- When you change or delete notification/hook-related scripts (`home/dot_claude/scripts/`, `home/dot_claude/hooks/`, `home/dot_codex/`, etc.) or helpers under `home/bin/`, check that references in the corresponding tests have not become stale.
- After changes, also run `chezmoi apply` in Docker locally and check the result.

## Documentation Update Rules

- When you change the repository structure, commands, tests, or security policy, update the following documents to match reality:
  - `README.md`: instructions and feature descriptions for users.
  - `CLAUDE.md`: working policy for Claude Code (this file).
  - `.github/copilot-instructions.md`: review guidelines for GitHub Copilot code review.
- Agent instructions for this repository are consolidated in 3 files: `AGENTS.md` (language policy only) / `CLAUDE.md` / `.github/copilot-instructions.md`. The global instructions for Codex CLI are managed separately in `home/dot_codex/AGENTS.md` (deployed as `~/.codex/AGENTS.md`).

## Repository-Specific

- Git settings are managed in `~/.gitconfig.local` (outside chezmoi management).
- Notification environment variables are managed in `~/.env` (outside chezmoi management).
- `.env.example` and `.gitconfig.local.example` are provided as samples.
- wakatime is managed separately, so dotfiles do not manage it with encryption.
- The PR target defaults to the `upstream` remote if one exists, and is resolved by `home/bin/executable_gh-pr-target-repo.sh` (deployed as `~/bin/gh-pr-target-repo.sh`).
- The reviewer (`book000`) at PR creation is resolved by `home/bin/executable_gh-pr-reviewer.sh` (deployed as `~/bin/gh-pr-reviewer.sh`) and passed to `gh pr create --reviewer`. If the PR author is `book000` themselves, or `book000` is not a collaborator, it prints nothing and the reviewer assignment is skipped.
- `home/bin/executable_write-session-state.sh` (deployed as `~/bin/write-session-state.sh`) writes the PR URL to `~/.claude/data/session-state.json` and prints it; the PR-creating skills (`issue-pr-deep`/`issue-pr-lite`, `glitchtip-pr-deep`/`glitchtip-pr-lite`, `ticket-pr`) call it instead of embedding the script. Keep git commands in skills as simple, separate calls with literal arguments, because Claude Code's worktree guard refuses compound commands that mix `$VAR` arguments with git.
- Dependency version updates are managed by Renovate (GitHub App) via `renovate.json`. Places that a regular `package.json` cannot track, such as the mise core version hard-coded in `install.sh`, are targeted individually with `regexManagers`. Versions of mise-managed tools such as `gh`/`ghq`/`roots`/`gitleaks`/`ccstatusline` are tracked automatically by Renovate's native mise support through their declaration in `home/dot_config/mise/config.toml` (no extra `regexManagers` configuration is needed).
- Never directly edit chezmoi deploy targets (everything expanded from `home/dot_*`, such as under `~/.claude/`). Always edit the corresponding source file under `home/dot_*`, and when verification is needed, apply it with `chezmoi apply` (or `chezmoi diff`). Directly editing a deploy target means it is silently overwritten and rolled back to the source contents by a later `chezmoi apply`/`chezmoi update` (including automatically run ones).
- When you rename / delete an existing managed file and also want it removed from the target side, add the old target path to `home/.chezmoiremove`. Never make a directory that holds runtime state, such as `.claude` / `.codex`, `exact_`.
- `chezmoi-update.service` / `.timer` are managed with `home/dot_config/systemd/user/` and enable symlinks, and when a unit changes, a run-on-change script reloads the user manager. The Linux daily timer uses `Persistent=true` and runs `update.sh --force`. `update.sh` at AI CLI startup uses a 24-hour throttle and `flock`, and when there is no TTY, it backs up locally modified managed files to `~/.cache/chezmoi-update/drift-backups/` before applying. After applying, it runs `mise install` with the managed global config (`~/.config/mise/config.toml`) specified explicitly, and records the update timestamp only if mise also succeeds.
- Keep `home/dot_claude/skills/deep-review/` self-contained so that it can be imported as a standalone ZIP. `SKILL.md` must not point to scripts or reference files outside the skill (under `~/.agents/` or `~/.claude/`), and references `scripts/`, `references/`, and `reviewers/` relative to `${CLAUDE_SKILL_DIR}`. Files under `scripts/` do not get the `executable_` prefix and are invoked via `bash`. Keep the contents in sync with the scripts and references of `home/dot_agents/skills/deep-review/` for Codex (verified by `tests/unit/test_deep_review_layout.sh`).
- `home/dot_claude/skills/check-container-status/` is a global skill that comprehensively checks the running status of a directory where many Docker Compose projects coexist (e.g. `/mnt/hdd/<machine name>`) using parallel sub-agents (`home/dot_claude/agents/container-status-checker.md` / `container-error-investigator.md`).
- `home/dot_claude/skills/proxmox/` is a global skill (`user-invocable: false`, called only from Claude Code) for operating Proxmox VE VMs through the REST API, QEMU guest agent and VNC console, including Japanese IME input on Windows guests. Credentials (`PROXMOX_URL` / `PROXMOX_USER` / `PROXMOX_PASSWORD`) come from `~/.env`; the helper scripts under `scripts/` are run via `bash` / `python3` without the `executable_` prefix.

- `home/dot_claude/hooks/executable_rtk-rewrite.sh` is verified by rtk against the pinned hash `home/dot_claude/hooks/readonly_dot_rtk-hook.sha256` (deployed as `~/.claude/hooks/.rtk-hook.sha256`, format `<sha256>  rtk-rewrite.sh`). On a mismatch rtk refuses to run every rewritten command ("RTK will not execute"). Whenever you change the hook, update the hash file in the same commit: `printf '%s  rtk-rewrite.sh\n' "$(sha256sum home/dot_claude/hooks/executable_rtk-rewrite.sh | cut -d' ' -f1)" > home/dot_claude/hooks/readonly_dot_rtk-hook.sha256`. `tests/unit/test_rtk_hook_hash.sh` fails when they diverge. Do not refresh the deployed hash by hand: the next `chezmoi apply` restores the repo value.

## Claude Code Hooks / Notification Features

Claude Code hooks are configured in `home/dot_claude/private_settings.json` and use `Stop` / `SubagentStop` / `PreToolUse` / `PostToolUse` / `PermissionRequest` / `Notification` / `UserPromptSubmit`. Their roles fall broadly into 2 groups:

- **Discord notifications**: scripts under `home/dot_claude/scripts/completion-notify/` (session completion, permission requests, AskUserQuestion, Notification, etc.). They use `DISCORD_CLAUDE_WEBHOOK` and `DISCORD_CLAUDE_MENTION_USER_ID` from `~/.env`.
- **Review enforcement, etc.**: scripts under `home/dot_claude/hooks/` (deep-review (by default it runs in review mode and does not block; it blocks only when the `--fix` mode ledger has an unresolved must-fix-before-merge finding; `lite-review` is judged by the same ledger; the Stop hook does not block while a background sub-agent is running), unresolved review thread check (the Stop hook resolves owner/repo/number from the PR URL, not from `origin`), rtk rewriting, git config guard, etc.). In addition, `executable_detect-leaked-toolcall.sh`, as a concern separate from review enforcement, detects leakage of tool-call XML markup into assistant messages on both `Stop` and `SubagentStop`.

When you change a hook command or its target script, check that references in `tests/unit/test_hooks.sh` / `test_notifications.sh` have not become stale.

The git config guard analyzes the command as shell syntax (quotes, heredocs, redirects, `$(...)`, `bash -c`, container mounts) so that the words only appearing as data are allowed. The shared logic lives in `git-config-guard-lib.sh`, which is deployed next to `git-config-guard.sh` in both `~/.claude/hooks/` and `~/.codex/hooks/` as byte-identical copies (checked by `tests/unit/test_git_config_guard.sh`). Without the `executable_` prefix it is deployed non-executable and is only sourced. When you change it, edit both copies and run `tests/unit/test_hooks.sh` and `tests/unit/test_git_config_guard.sh`.

## Git Hook (Secret Scanning)

`home/dot_config/git/hooks/executable_pre-commit` (deployed as `~/.config/git/hooks/pre-commit`) is registered as the global pre-commit hook via `core.hooksPath` and scans the staged diff for secrets with `gitleaks`. The fallback configuration is `home/dot_gitleaks.toml` (deployed as `~/.gitleaks.toml`).

When you change this hook or how the `gitleaks` command itself is installed (mise management via `home/dot_config/mise/config.toml`, `install_mise_tools` in `install.sh`), check that references in `tests/unit/test_hooks.sh` / `tests/unit/test_install.sh` / `tests/integration/test_chezmoi_apply.sh` / `tests/integration/test_gitleaks.sh` have not become stale.
