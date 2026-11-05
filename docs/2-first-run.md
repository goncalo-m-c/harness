# First run

## What you need

- **Claude Code.** It is the only tool with install notes now.
- **Docker.** The engine, openspec and ruff run in Docker.
- **`gh`**, logged in to GitHub. The PR phase uses it.
- **A repo in the git-wt layout**: the `main` branch sits in `<repo>/main`, and each branch gets its own worktree folder next to it.
- **`git-wt`**, the tool for that layout. Install it with brew: `brew tap ahmedelgabri/git-wt`, then `brew install git-wt`.
- **One parent folder, `ROOT`,** that holds your repos, the harness and the store. The engine runs in Docker and sees only this folder.
- **Optional:** three terminal tools that open things in a new tab. Without them, the agent prints the paths instead.
  - `herdr` manages the terminal tabs.
  - `glow` shows the spec as formatted text.
  - `hunk` shows the commits and their diffs.
  - They also need `jq`.

## Skills from outside this repo

The phases call two skills that this repo does not contain. Install them before your first run.

| Skill | What the harness uses it for | Where the harness looks for it |
|---|---|---|
| `grilling` | the question rounds in the grill phase | by name, as a Claude Code skill |
| `code-review` | the two review sides: spec and standards | `~/Projects/.agents/skills/code-review/SKILL.md` |

Two more skills come with the install. The `git-wt` tool writes its own skill with `git wt agent-skill`.
`pr-description`, the three sections of the PR text, is in this repo.

## Install

Open Claude Code in the harness folder and run `/harness-setup`. It walks you through each step and asks before it changes anything.

To do it by hand, follow two files in order:

1. [`README.md`](../README.md), section "Install": build the engine image and create the store.
2. [`clients/claude.md`](../clients/claude.md): connect the engine, link the skills, agents and rules, and add the permission rules.

Restart Claude Code at the end. It loads skills, rules and MCP servers only at start.

## Your first ticket

This example adds a login page to the repo `~/Projects/my-repo`.

**1. Start the run.** Describe the work in your own words:

    /work add a login page

The agent shows a table with one model for each subagent, and the key prefixes already in use. Confirm the models or change one.
Pick a prefix, for example `ABC`. The engine gives the next free key, here `ABC-1`, and saves your words in the store.
If you already have a ticket key (from Jira, for example), give that instead.

**2. Grill.** The agent asks you questions until the two of you agree on what to build.
It looks up facts in the code itself and asks you only for decisions.
At the end it shows you the list of decisions. You also agree on a short name (the slug), like `add-login`, and the repo.
When you confirm, the engine saves the decisions and names the branch `abc-1-add-login`.

**3. Spec.** A subagent turns the decisions into a spec: a proposal, a design and a task list.
The spec opens in a new tab. Read it. If it is right, say yes. Claude Code then asks you to allow `work_approve`.

**4. Implement.** The agent creates the worktree `~/Projects/my-repo/abc-1-add-login`.
A subagent writes the code there and commits each step. Then the commits open in hunk, in a new tab.
Ask for changes now, before the review. When you are happy, say go.

**5. Review.** Two subagents review the code: one against the spec, one against the code rules.
A finding marked `hard` must be fixed. The agent sends those fixes to the implementer and runs the reviewers again.
When both reviews are clean, press `r` in the hunk tab to see the new commits.
Then approve the push. Claude Code still asks you once more when the push happens.

**6. PR and CI.** A subagent pushes the branch, opens a draft PR and waits for the CI checks.
If a check fails, the agent shows you the cause and asks before it fixes and pushes again.
If CI takes longer than about 20 minutes, the agent tells you, and you ask it to wait again later.
When CI is green, the run is done.

The agent is told never to merge the PR or mark it ready. Permission rules also block both. You do that yourself.

## If you stop halfway

Run `/work ABC-1`. See [Daily use](4-daily-use.md#resuming-a-run).

Next: [Phases](3-phases.md).
