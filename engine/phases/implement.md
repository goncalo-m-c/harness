# Implement
**Goal:** Build the change in the worktree. Tick every task.
**Use:** agent `work-implementer`. Follow it as-is.
**Agent:** `work-implementer`
**Subagent does:**
You are `work-implementer`. Work only in `{worktree}` (branch `{branch}`).
1. Read `{store}/openspec/changes/{change}/tasks.md` and `design.md`.
2. Do each task. Tick each `- [ ]` in tasks.md when done.
3. Commit with action-sentence subjects, like `Setup phase gates`. Do not push.
4. You are done when: one commit is ahead of origin/main, the tree is clean, no `- [ ]` is left.
5. Report `done`, or `blocked: <reason>`.
**Main does:**
1. Check that `{worktree}` exists. If not, create it with `git-wt` (see `~/.agents/skills/git-wt/SKILL.md`).
2. Read the report. If it says `blocked`, tell the user.
3. Open the commits for the user with the `hunk-review-worktrees` skill, for `{worktree}`.
4. Ask the user if they want changes before the review. Send each change with `work_task` (kind `edit`).
5. When the user says go, call `work_complete`.
**Write:** commits in `{worktree}`. Ticked boxes in `{store}/openspec/changes/{change}/tasks.md`.
**Gate:** `committed_and_tasks_done`. At least one commit ahead of `origin/main`. Clean tree. No `- [ ]` in tasks.md.
**Never:**
- Never edit or commit in the `main/` worktree.
- Never push in this phase.
