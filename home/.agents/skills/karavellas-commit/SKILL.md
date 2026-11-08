---
name: karavellas-commit
description: Commit changes from the current conversation when the user asks to commit or invokes karavellas-commit. Select only conversation-related hunks, run existing tests, and never push.
---

# Karavellas commit

When invoked, create the commit immediately after the review and checks below.
Do not ask for routine approval of the selected changes or commit message.
Never push, **only** when requested alongside this skill.
Do not invoke this workflow merely because you created or edited the skill.
Never invoke the skill because is seems logical too, this skill should be invoked
by the user.

## Select the changes

1. Read the repository instructions and review Git status, the working-tree
   diff, and the staged diff. Use the current conversation to identify the
   intended changes; do not assume every modified file belongs to this task.
2. Include only hunks attributable to the current conversation. Inspect new
   files too. Exclude unrelated edits, generated noise, credentials, and secrets.
3. Stage selectively, including partial-file hunks when needed. Never use
   blanket staging such as `git add .` or `git add -A`.
4. Preserve unrelated working-tree and staged changes. If unrelated changes
   are already staged, isolate this commit without including or discarding
   them, and preserve their staged state afterward. If safe separation is
   unclear, stop and explain the blocker rather than guessing.
5. Review the exact proposed commit diff. If no conversation-related changes
   remain, report that there is nothing to commit.
6. When you commit, inform about the state of the repo,
   and if anything got left behind because it was out of scope, Be brief and answer
   in bullet points


## Run checks

1. Look for the codebase's documented test commands and existing test suites.
2. If tests exist, run the relevant existing tests before committing. Run the
   full suite when practical; explain any limited coverage.
3. If tests fail or cannot run, do not commit. Report the failure or blocker;
   do not silently bypass checks or install dependencies without permission.
4. If the codebase has no tests, say so in the final summary; do not invent a
   test suite merely to create a commit.

## Write the message

Use this format, with a blank line between the title and the bullet list:

```text
feat(scope): brief title

- Brief detail about the change.
- Another relevant detail, if needed.
```

- Choose the appropriate Conventional Commit type, such as `feat`, `fix`,
  `refactor`, `docs`, `test`, or `chore`; do not always use `feat`.
- Always include a concise scope identifying the affected component.
- Keep the title brief, imperative, and without a trailing period.
- Include a brief body using `- ` bullets. Describe meaningful changes and
  reasons, not a file-by-file transcript. One bullet is sufficient when apt.
- Do not claim checks passed unless they actually ran successfully.
- Don't mention any ran test or unnecessary information in the commit message
- Your brief details on the commit message, should actually be brief

## Commit and report

1. Create a new commit containing only the reviewed, conversation-related
   hunks. Do not amend, rewrite history, bypass hooks, or change Git identity.
2. If a hook fails, stop and report it; do not bypass the hook.
3. Check Git status afterward and confirm unrelated changes are preserved.
4. Report the commit hash and title, checks run, and any remaining changes.
5. NEVER PUSH. Do not run `git push` or any equivalent operation that uploads
   commits, pushes tags, or publishes repository changes, unless specifically asked
