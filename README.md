# harness

A small workflow harness for AI coding agents. It drives one piece of work through fixed phases:

grill → spec → (you approve) → implement → review → (you approve the push) → PR → CI

A local MCP server (the engine) owns the state and checks a gate before each phase can end.
The agent cannot skip a phase, because it can only move forward by passing a gate.

```
engine/       MCP server, pipeline.yaml (the map), phases/ (instructions per phase), Dockerfile
skills/       work (the entry skill), review-rules (language rules for the review)
agents/       subagents used by the phases (spec, implement, review, PR, CI, explore)
rules/        shared rules for agents: git, code style, commands, communication, subagents
hooks/        block-host-python.sh (Claude Code hook: python only inside Docker)
```

Start with `engine/README.md`.

## Not in this repo yet

- Install steps for Cursor and Claude Code.
- Cost per model.
- Tests for the engine.

## Skills this repo expects but does not contain

`grilling`, `pr-description`, `git-wt`, `code-review`. Phases and agents point to them by name.
