# First run

## What you need

- **Claude Code.** It is the only tool with install notes now.
- **Docker.** The engine, openspec and ruff run in Docker.
- **`gh`**, logged in to GitHub. The PR phase uses it.
- **A repo in the git-wt layout**: the `main` branch sits in `<repo>/main`, and each branch gets its own folder next to it.
- **Optional:** `herdr`, `hunk`, `glow` and `jq`. They open the spec and the code in a new terminal tab.
  Without them, the agent prints the paths instead.
- **Skills from outside this repo:** `grilling`, `pr-description`, `git-wt`, `code-review`. The phases call them by name.

## Install

Open Claude Code in the harness folder and run `/harness-setup`. It walks you through each step and asks before it changes anything.

To do it by hand, follow two files in order:

1. [`README.md`](../README.md), section "Install": build the engine image and create the store.
2. [`clients/claude.md`](../clients/claude.md): connect the engine, link the skills, agents and rules, and add the permission rules.

Restart Claude Code at the end. It loads skills, rules and MCP servers only at start.

## Your first ticket

This example uses the ticket `ABC-123`, the short name `add-login` and the repo `~/Projects/my-repo`.

**1. Start the run.**

    /work ABC-123 add-login ~/Projects/my-repo

The agent shows a table with one model for each subagent. Confirm it or change a model.

**2. Grill.** The agent asks you questions until the two of you agree on what to build.
It looks up facts in the code itself and asks you only for decisions.
At the end it shows you the list of decisions. When you confirm, the engine saves them.

**3. Spec.** A subagent turns the decisions into a spec: a proposal, a design and a task list.
The spec opens in a new tab. Read it. If it is right, say yes. Claude Code then asks you to allow `work_approve`.

**4. Implement.** A subagent writes the code in a new branch folder, `~/Projects/my-repo/abc-123-add-login`.
It commits each step. Then the commits open in hunk, in a new tab.
Ask for changes now, before the review. When you are happy, say go.

**5. Review.** Two subagents review the code: one against the spec, one against the code rules.
A finding marked `hard` must be fixed. The agent sends those fixes to the implementer and runs the reviewers again.
When both reviews are clean, press `r` in the hunk tab to see the new commits.
Then approve the push.

**6. PR and CI.** A subagent pushes the branch, opens a draft PR and waits for the CI checks.
If a check fails, the agent shows you the cause and asks before it fixes and pushes again.
When CI is green, the run is done.

The agent never merges the PR and never marks it ready. You do that yourself.

## If you stop halfway

Run `/work ABC-123`. The engine knows the phase, and it shows the latest checkpoint.
See [Daily use](4-daily-use.md) for checkpoints.

Next: [Phases](3-phases.md).
