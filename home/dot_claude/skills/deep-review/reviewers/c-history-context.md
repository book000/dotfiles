---
id: c
name: history-context
title: History context (git history / past PR comments)
applies_to: all
---

## Scope

Check `git blame` and `git log` for changed files. Report issues only when
historical context reveals a problem that is not visible from the diff alone.

**PR mode only**: also find recently merged PRs that touched the same files
(`gh pr list --state merged`). Check their review comments for concerns that
may also apply here. In local diff mode, skip this part — there is no PR to
compare against.
