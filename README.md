# harness

A workflow harness for AI coding agents. The agent does the work. A small engine decides when each step is done.

```
grill → spec → [you approve] → implement → review → [you approve the push] → pr → ci
```

## Why

Give a coding agent a full ticket and it often skips steps.
It starts to code before the plan is clear.
It says the tests pass when it did not run them.
It pushes before anyone looked at the diff.

Rules in a prompt help, but the agent can still ignore them.
This harness moves the rules out of the prompt and into code.

A local MCP server (the engine) holds the state of each piece of work.
The agent can only go to the next phase through the engine.
Before it lets the agent move on, the engine checks a **gate**: a small function that looks at real files, git or GitHub.
If the gate fails, the agent gets the reasons and must fix them.

## The phases

| Phase | Who does it | Gate (checked in code) |
|---|---|---|
| grill | the main chat, with you | `decisions.md` exists and is not empty |
| spec | `work-spec-writer` | `openspec validate --strict` passes. Then **you approve**. |
| implement | `work-implementer` | at least one commit ahead of `origin/main`, clean tree, every task ticked |
| review | `work-reviewer-spec` and `work-reviewer-standards`, in parallel | both reports are newer than the last commit and have no `hard` finding. Then **you approve the push**. |
| pr | `work-pr` | the remote branch is at the local `HEAD`. The PR is a draft. |
| ci | `work-ci-watcher` | the saved CI result is for `HEAD` and every check passed |

The agent never merges and never marks a PR ready. That stays with you.

## How it works

```
 you <-> agent chat  (/work KEY SLUG REPO)
            |  MCP over stdio (docker run -i)
            v
   engine:  work_start | work_next | work_complete | work_approve | work_task
            |
            +-- pipeline.yaml   phases, gates, approvals, model per subagent
            +-- phases/*.md     what to do in each phase
            +-- gates.py        one function per gate
            v
   <store>/runs/<KEY>/state.json  +  decisions.md, reviews/, ci/
```

A run goes like this:

1. You type `/work ABC-123 my-slug /path/to/repo`. The `work` skill tells the agent to call `work_start`.
2. The engine shows a model for each subagent. You confirm or change them.
3. `work_next` returns the instructions for the current phase. For a subagent phase, it returns a ready dispatch: the agent, the model and the full prompt.
4. When the phase looks done, the agent calls `work_complete`. The engine runs the gate.
5. If the gate passes, the run moves on. If it fails, the agent gets the reasons.
6. Two phases wait for you. Only `work_approve` moves past them, and a permission rule makes that tool ask you each time.

## Design choices

- **The engine owns the state. The agent owns the conversation.** Only the engine writes `state.json`. A deny rule stops the agent from editing it.
- **Gates check facts, not claims.** The review gate counts the `- hard:` lines in the reports itself. The CI gate reads the raw `gh` output, saved for the current commit.
- **The reviewer is not the implementer.** The engine refuses a setup where a reviewer uses the same model as the implementer.
- **Rules travel with the work.** Subagents do not see the main chat. The engine pastes the rule files from `rules/` into each subagent prompt.
- **Skip attempts are logged.** Each failed gate or refused call goes into the run history, so you can count how often the agent tried to skip.
- **The main chat stays small.** Edits and investigations go to subagents through `work_task`. The main chat gets a summary.
- **Python runs only in Docker.** An optional hook blocks `python`, `uv` and `pytest` on the host.

## Repo layout

| Folder | What is inside |
|---|---|
| `engine/` | The MCP server, `pipeline.yaml`, `phases/`, the gates, tests and the Dockerfile. Start with [`engine/README.md`](engine/README.md). |
| `skills/` | `work` (the entry skill), `review-rules` (language rules for the review), `hunk-review-worktrees` (opens the code for your review) |
| `agents/` | The subagents: spec, implement, review, PR, CI and explore |
| `rules/` | Shared rules: git, code style, commands, communication, subagents |
| `settings/` | Permission rules for Claude Code. See [`settings/README.md`](settings/README.md). |
| `hooks/` | `block-host-python.sh`: a Claude Code hook that keeps Python inside Docker |
| `scripts/` | `open-spec-tab.sh`: opens a spec in a new terminal tab |
| `clients/` | One install note per tool. Only [`clients/claude.md`](clients/claude.md) for now. |
| `.claude/` | `harness-setup` and `link-hunk-review`: skills that work before anything is installed |

## Install

You need Docker, Claude Code, `git` and the GitHub CLI (`gh`), logged in.
Optional: `herdr` and `glow` to open specs in a tab, and `hunk`, `herdr` and `jq` to open the code review in a tab.

Open Claude Code in this folder and run `/harness-setup`, or follow the steps yourself.
Set `STORE` to the folder where runs and specs will live.

1. Build the engine and create the store. This is the same for every tool.

       docker build -t work-engine:poc engine
       mkdir -p "$STORE" && docker run --rm -v "$STORE:$STORE" work-engine:poc openspec init --tools none "$STORE"

2. Connect your tool: [`clients/claude.md`](clients/claude.md). A new tool needs one new file in `clients/`.

## Run the tests

The tests run inside the engine image:

    docker run --rm -v "$PWD/engine:/e" -w /e work-engine:poc python -m unittest test_gates -v

## Limits

This is a personal proof of concept. I use it for my own work.

- Only Claude Code has install notes. Cursor is next.
- The tests cover the review gate only.
- The permission rules are not a wall. A command inside `bash -c "..."` can go around them. See [`settings/README.md`](settings/README.md).
- It works with GitHub only, because the PR and CI phases use `gh`.
- The repo must use the `git-wt` layout: each branch is a worktree folder inside the repo folder.
- There is no cost tracking per model yet.

## Skills this repo expects but does not contain

`grilling`, `pr-description`, `git-wt` and `code-review`. The phases and agents point to them by name.
