# harness

A small workflow harness for AI coding agents. It drives one piece of work through fixed phases:

grill → spec → (you approve) → implement → review → (you approve the push) → PR → CI

A local MCP server (the engine) owns the state and checks a gate before each phase can end.
The agent cannot skip a phase, because it can only move forward by passing a gate.

```
engine/       MCP server, pipeline.yaml (the map), phases/ (instructions per phase), Dockerfile
skills/       work (the entry skill), review-rules (language rules for the review), hunk-review-worktrees (opens the code for your review)
agents/       subagents used by the phases (spec, implement, review, PR, CI, explore)
rules/        shared rules for agents: git, code style, commands, communication, subagents
hooks/        block-host-python.sh (Claude Code hook: python only inside Docker)
settings/     permission rules for settings.json (see settings/README.md)
clients/      one install note per tool (claude.md)
.claude/      harness-setup and link-hunk-review skills (work before anything is installed)
```

Start with `engine/README.md`.

## Install

Open Claude Code in this folder and run `/harness-setup`, or follow the steps yourself.
You need Docker. Set `STORE` to the folder where runs and specs will live.

1. Build the engine and create the store. This is the same for every tool.

       docker build -t work-engine:poc engine
       mkdir -p "$STORE" && docker run --rm -v "$STORE:$STORE" work-engine:poc openspec init --tools none "$STORE"

2. Connect your tool: [`clients/claude.md`](clients/claude.md). A new tool needs one new file in `clients/`.

## Not in this repo yet

- Install notes for Cursor (`clients/cursor.md`).
- Cost per model.
- Tests for the engine.

## Skills this repo expects but does not contain

`grilling`, `pr-description`, `git-wt`, `code-review`. Phases and agents point to them by name.
