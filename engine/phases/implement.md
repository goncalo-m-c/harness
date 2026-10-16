# Implement
**Goal:** Build the change in the worktree. Tick every task.
**Use:** agent `work-implementer`. Follow it as-is.
**Agent:** `work-implementer`
**Subagent does:**
You are `work-implementer`. Work only in `{worktree}` (branch `{branch}`).
1. Read `{store}/openspec/changes/{change}/tasks.md` and `design.md`.
2. Do each task. Tick each `- [ ]` in tasks.md when done.
3. Commit with conventional commits. Do not push.
4. You are done when: one commit is ahead of origin/main, the tree is clean, no `- [ ]` is left.
5. Report `done`, or `blocked: <reason>`.
**Main does:**
1. Check that `{worktree}` exists. If not, create it with `git-wt` (see `~/.agents/skills/git-wt/SKILL.md`).
2. Read the report. If it says `blocked`, tell the user.
3. Call `work_complete`.
**Write:** commits in `{worktree}`. Ticked boxes in `{store}/openspec/changes/{change}/tasks.md`.
**Gate:** `committed_and_tasks_done`. At least one commit ahead of `origin/main`. Clean tree. No `- [ ]` in tasks.md.
**Never:**
- Never edit or commit in the `main/` worktree.
- Never push in this phase.
