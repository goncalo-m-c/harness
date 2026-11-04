# Claude Code

Connect the harness to Claude Code. Do the README install step 1 first (image and store).

Set these in your shell. Use full paths.

    HARNESS=~/Projects/harness/main # the main checkout of this repo (git-wt layout: <repo>/main)
    STORE=~/Projects/work-store     # runs and specs (README step 1)
    ROOT=~/Projects                 # the folder that holds your repos. The engine only sees this folder.

## 1. Add the MCP server

    claude mcp add work --scope user -- docker run -i --rm \
      -v "$ROOT:$ROOT" -v "$STORE:$STORE" -e "WORK_STORE=$STORE" \
      work-engine:poc python "$HARNESS/engine/engine.py"

Check it with `claude mcp get work`.

## 2. Link the skills and agents

The phase text points to `~/.agents/skills`, so the skills go there first. Claude Code links to them.
If a path already exists as a real folder, `ln` would put the link inside it. Check with `ls -ld` first.
`hunk-review-worktrees` needs `hunk`, `herdr` and `jq`. To add only this skill, run `/link-hunk-review` in this repo.

Install `git-wt` and its skill. The implement phase uses them to create the worktree.
`git wt agent-skill` writes `~/.agents/skills/git-wt/SKILL.md`.

    brew tap ahmedelgabri/git-wt
    brew install git-wt
    git wt agent-skill

Then link all skills:

    mkdir -p ~/.agents/skills ~/.claude/skills ~/.claude/agents
    for s in work review-rules hunk-review-worktrees pr-description; do
      ln -sfn "$HARNESS/skills/$s" ~/.agents/skills/$s
      ln -sfn ~/.agents/skills/$s ~/.claude/skills/$s
    done
    for f in "$HARNESS"/agents/work-*.md; do
      ln -sfn "$f" ~/.claude/agents/$(basename "$f")
    done
    ln -sfn ~/.agents/skills/git-wt ~/.claude/skills/git-wt

Link the global ruff config. Ruff uses it in repos that have no ruff config of their own.
Agents run ruff in Docker, and the image reads this file.

    mkdir -p ~/.config/ruff
    ln -sfn "$HARNESS/settings/ruff/ruff.toml" ~/.config/ruff/ruff.toml
    docker pull ghcr.io/astral-sh/ruff:0.17.1

Link the language rules. Claude Code loads a rule file when an agent reads or edits a matching file,
in the main session and in subagents. The `paths:` list at the top of the file says which files match.

    mkdir -p ~/.claude/rules
    ln -sfn "$HARNESS/skills/review-rules/rules/python.md" ~/.claude/rules/python.md

## 3. Add the permission rules

Copy the `deny` and `ask` lists from `settings/permissions.example.json` into `~/.claude/settings.json`, under `permissions`.
If you already have those lists, add the entries to them. Save a copy first: `cp ~/.claude/settings.json ~/.claude/settings.json.bak-harness`.

Optional: block python outside Docker. Add this under `hooks.PreToolUse` (replace `<HARNESS>` with the full path):

    {"matcher": "Bash", "hooks": [{"type": "command", "command": "<HARNESS>/hooks/block-host-python.sh"}]}

## 4. Restart and check

Restart Claude Code. Rules and MCP servers load at start. Then:

1. Run the 5-step test in `settings/README.md`, in a throwaway git repo.
2. Ask Claude to call `work_start` with a key, a slug and a repo path, and no `models`. It must return the model table and create nothing.
