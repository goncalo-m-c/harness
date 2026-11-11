# Claude Code

Connect the harness to Claude Code. Do the README install step 1 first (image and store).

Set these in your shell. Use full paths.

    HARNESS=~/Projects/harness/main # the main checkout of this repo (git-wt layout: <repo>/main)
    STORE=~/Projects/work-store     # runs and specs (README step 1)
    ROOT=~/Projects                 # the folder that holds your repos. The engine only sees this folder.

## 1. Add the MCP server

    claude mcp add work --scope user -e WORK_PROJECT=<owner>/<number> -- \
      bash "$HARNESS/scripts/run-engine.sh" "$ROOT" "$STORE" "$HARNESS"

`WORK_PROJECT` is the owner and number of the GitHub project board. Take both from its URL, like `github.com/users/<owner>/projects/<number>`. The board is optional: without `WORK_PROJECT`, the engine skips it.
The script starts the engine container and reads the board tokens from your keychain (see below).

### GitHub tokens

The board needs two tokens. GitHub cannot give a narrower token for a project owned by a personal account. So a classic token is the smallest choice for the board.

- `factory-board`: a classic token with only `project`, `read:org` and `read:discussion`. The last two are read-only, but `gh project` refuses to run without them. The engine uses it for every board call.
- `factory-issues`: a fine-grained token with only Issues: read and write, on the repos you pick. The engine uses it to write comments.

Make both with a short expiry, like 30 days. Store each one in the keychain. The command asks for the value, so it never shows in your shell history or the process list:

    security add-generic-password -U -s factory-board -a "$USER" -w
    security add-generic-password -U -s factory-issues -a "$USER" -w

`scripts/run-engine.sh` reads them from the keychain and gives them to the container. The tokens are not in your shell environment or in the MCP config.
But any program that runs as you can read them. `security find-generic-password` reads the keychain item without asking, and `docker inspect` shows the container's env. So an agent with Bash can read them.
Neither token can push code or change CI. Three things limit the damage:

- The narrow scopes above.
- The deny rules in `settings/permissions.example.json` (step 3).
- Optional: store the items with `-T ""`, as in `security add-generic-password -U -T "" -s factory-board -a "$USER" -w`. Then macOS asks you on every read, so at every engine start.

Check it with `claude mcp get work`.

## 2. Link the skills and agents

The phase text points to `~/.agents/skills`, so the skills go there first. Claude Code links to them.
If a path already exists as a real folder, `ln` would put the link inside it. Check with `ls -ld` first.
`hunk-review-worktrees` needs `hunk`, the Herdr app and `jq`. To add only this skill, run `/link-hunk-review` in this repo.

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

Link the `spec-viewer` mod into the Herdr app. The spec phase opens it beside the agent.
Then check it: the app must print `Check passed`.

    ln -sfn "$HARNESS/herdr-app/mods/spec-viewer" ~/.config/herdr-app/mods/spec-viewer
    herdr-app check ~/.config/herdr-app/mods/spec-viewer

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
2. Ask Claude to call `work_start` with a description and no `models`. It must return the model table and the key prefixes, and create nothing.
