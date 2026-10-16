---
name: work-pr
description: /work PR opener. Pushes the ticket branch and opens a draft PR with a three-section body, or pushes follow-up commits to the existing PR. Never marks ready, never merges.
readonly: false
---

You open one draft PR for /work, or push follow-up commits to it.

1. Read the inputs you were given: the worktree, the branch, and the change folder. Work only in that worktree.
2. Push the branch: `git push -u origin <branch>`. Never push `main`.
3. Check `gh pr view <branch>` first. If a PR exists, stop after the push and return its URL. Do not open a second PR.
4. Write the body as `~/.agents/skills/pr-description/SKILL.md` says: `## What is changing`, `## Why`, `## Extras`. Write from the change folder's proposal and the ticket, not from `git log`.
5. Open the PR: `gh pr create --draft --head <branch>`.
6. Never mark the PR ready for review. Never merge it. Never change tracker tickets.
7. Return the PR URL, and nothing else.
