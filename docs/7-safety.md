# Safety

The harness has four layers of protection. Each one catches different mistakes.

## 1. Gates

The engine checks the real state before a phase can end. See [Phases](3-phases.md).
An agent cannot pass a gate by saying the work is done.

## 2. Your approvals

Two steps need your yes: the spec, and the push after review.
Only you can approve. Claude Code asks you each time `work_approve` is called.
Never add `work_approve` to an allow list.

## 3. Permission rules

[`settings/permissions.example.json`](../settings/permissions.example.json) holds rules for `~/.claude/settings.json`.
They apply to the chat agent and to every subagent.

| Rule | Effect |
|---|---|
| deny edits to `runs/**/state.json` | No agent changes the run state by hand. |
| deny `gh pr merge`, `gh pr ready` | No agent merges a PR or marks it ready. |
| deny `git push ... main` or `master` | No agent pushes to the main branch. |
| ask for every other `git push` | You see each push before it happens. |
| ask for `work_approve` | Each approval asks you. |

`deny` always wins over `ask` and `allow`.
See [`settings/README.md`](../settings/README.md) for a short test of these rules.

## 4. Hooks

[`hooks/block-host-python.sh`](../hooks/block-host-python.sh) is an optional Claude Code hook.
It blocks `python`, `pip`, `uv` and `pytest` on your machine, and allows them inside `docker run` or `docker exec`.
So agent code runs in a container, not directly on your computer.

## What the agents may never do

These rules are in the phase files and the agent files:

- Merge a PR, or mark it ready for review.
- Push to `main`, or push a fix without your yes.
- Edit or commit in the `main` folder of your repo.
- Edit `state.json`, or write a review report by hand.

## The limits

These protections are not a wall. Know what they do not stop:

- A command hidden in `bash -c "..."`, or a script that writes a file, can get around the permission rules.
- In `dontAsk` mode, every `ask` becomes a refusal. Do not use that mode with this harness.
- Gates check facts, not quality. A review with no `hard` finding can still miss a bug. Read the code yourself in hunk.

Next: [Extending](8-extending.md).
