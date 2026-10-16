# PR
**Goal:** Push the branch and open a draft PR.
**Use:** skill `pr-description`. Follow it as-is.
**Agent:** `work-pr`
**Subagent does:**
You are `work-pr`. Worktree: `{worktree}`. Branch: `{branch}`. Change folder: `{store}/openspec/changes/{change}/`.
1. Push: `git -C {worktree} push -u origin {branch}`.
2. Write the body from the spec goal and ticket, in the three sections of `pr-description`.
3. Open the PR: `gh pr create --draft --head {branch}`.
4. Report the PR URL.
**Main does:**
1. Call `work_complete` with the PR URL as `evidence`.
2. Give the user the PR URL.
**Write:** the draft PR on GitHub. Nothing in `{store}`.
**Gate:** `branch_pushed`. `refs/remotes/origin/{branch}` equals `HEAD` in `{worktree}`.
**Never:**
- Never mark the PR ready for review.
- Never merge the PR.
- Never push to `main`.
