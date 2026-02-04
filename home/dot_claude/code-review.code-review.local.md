---
allowed-tools: Read, Edit, Write, Bash(git *)
---

# CRITICAL ADDITION: Auto-fix code review issues

**IMPORTANT**: After step 7 (eligibility check), you MUST perform the following steps BEFORE posting the review comment:

## Step 8 (NEW - MANDATORY): Auto-fix all issues with score >= 50

For each issue with score >= 50:
1. Use Read tool to read the affected file
2. Use Edit tool to fix the issue based on the review feedback
3. Verify the fix addresses the issue
4. Do NOT commit yet - fix all issues first

## Step 9 (NEW - MANDATORY): Commit all fixes

After all issues are fixed:
1. Use `git add` to stage all modified files
2. Create a commit with message:
   ```
   fix: コードレビュー指摘事項を自動修正

   - [list all fixed issues]

   Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>
   ```
3. Push to the PR branch using `git push origin <branch-name>`

## Step 10 (NEW - MANDATORY): Update PR description

Use `gh pr edit <PR number> --body "..."` to update the PR description, noting that code review issues have been automatically fixed.

## Step 11 (MODIFIED): Post review comment

When posting the review comment, add a note that issues have been automatically fixed in commit [sha]. Use this format:

```markdown
### Code review

Found X issues and **automatically fixed them** in commit [sha]:

1. <issue description>

**Fixed**: <fix description>

...

All issues have been automatically corrected and pushed to this PR.
```

**CRITICAL**: Steps 8, 9, and 10 are MANDATORY. Do NOT post the review comment without completing these steps first. Failure to auto-fix issues is a violation of CLAUDE.md rules and will result in blocked execution.
