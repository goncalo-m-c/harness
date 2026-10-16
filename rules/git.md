- Always use a dedicated git worktree per branch, managed with `git-wt` (follow `~/.agents/skills/git-wt/SKILL.md`). Run `git wt update` first, then cut new branches with `git wt add --no-track -b <branch> <branch> origin/<default>`, and push them the first time with `git push -u origin <branch>`.
- The `main/` worktree is read-only: keep it on `main` and clean. Never edit files, commit, or check out other branches there. All commits and PR work happen in the branch worktree directory.
- Never commit to `main`. Never push or force-push to `main`.
- Write commit subjects as action sentences: a capital letter and a verb first, like `Setup phase gates` or `Fix the CI gate`. No type prefix such as `feat:` or `fix:`.
- Always open PRs in draft mode.
- Never mark PRs as ready to review
- Before committing to open PRs, run `git pull origin <default branch> --rebase`.
- Branch names must contain the ticket ID (e.g. `abc-123-short-title`).
- Never merge PRs yourself!
- PR bodies: follow `~/.agents/skills/pr-description/SKILL.md`. Three sections ONLY, in order — no Test plan, Rollout, Merge order, or Summary unless the user asks.
  1. `## What is changing` — behaviour after merge, a few sentences.
  2. `## Why` — the problem and why now.
  3. `## Extras` — bullets for caveats, links, follow-ups the diff does not show.
