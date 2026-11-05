---
name: link-hunk-review
description: Make the hunk-review-worktrees skill available in Claude Code on this computer. Run it from inside the harness repo.
disable-model-invocation: true
---

# Link hunk-review-worktrees

Claude Code finds a personal skill in `~/.claude/skills`. The harness keeps one copy of the skill in `skills/` and adds two links to it:

    ~/.claude/skills/hunk-review-worktrees -> ~/.agents/skills/hunk-review-worktrees -> <harness>/skills/hunk-review-worktrees

Links, not copies, so a `git pull` updates the skill.

Show each command before you run it. Wait for the user's yes before you change anything outside this repo.

1. Find the main checkout. Links must point there, because a worktree can be removed later.

       HARNESS=$(git worktree list --porcelain | awk '/^worktree /{p=$2} $0=="branch refs/heads/main"{print p}')
       ls "$HARNESS/skills/hunk-review-worktrees/SKILL.md"

   If the file is missing, the skill is not on that checkout's branch yet. Stop and tell the user.

2. Check the tools the skill runs:

       command -v hunk herdr jq

   If one is missing, name it to the user and keep going. The link still works, but the skill cannot open a review until the tool is installed.

3. Look for older copies. Check the two personal paths, and `.claude/skills/hunk-review-worktrees` in the current folder and each parent folder.

       ls -ld ~/.agents/skills/hunk-review-worktrees ~/.claude/skills/hunk-review-worktrees

   - A link to `$HARNESS`: keep it.
   - A link to anywhere else: show it and ask to remove it with `rm`.
   - A real folder: stop and ask the user. `ln` would put the new link inside it.

4. Add the links:

       mkdir -p ~/.agents/skills ~/.claude/skills
       ln -sfn "$HARNESS/skills/hunk-review-worktrees" ~/.agents/skills/hunk-review-worktrees
       ln -sfn ~/.agents/skills/hunk-review-worktrees ~/.claude/skills/hunk-review-worktrees

5. Check the links. This must print `name: hunk-review-worktrees`:

       sed -n 2p ~/.claude/skills/hunk-review-worktrees/SKILL.md

6. Tell the user to start a new Claude Code session and type `/hunk-review-worktrees`. The skill is available when that name appears in the list. Ask for the result.
