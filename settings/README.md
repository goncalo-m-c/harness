# Settings

Rules that keep an agent inside the harness. No scripts. Claude Code reads them from `settings.json`.

## How to use

Copy the `permissions` block of `permissions.example.json` into `~/.claude/settings.json`. Merge it with what you already have.

## What the rules do

| Rule | Effect |
|---|---|
| `deny Edit(**/runs/**/state.json)` | No agent edits a run's `state.json`. Shell writes like `sed` and `>` are covered too. |
| `deny gh pr merge`, `gh pr ready` | No agent merges a PR or marks it ready. |
| `deny git push ... main` or `master` | No push to main. Both `git push` and `git -C <path> push` are listed. |
| `deny security find-generic-password`, `docker inspect`, `docker exec` (and the `docker container` forms) | Blocks the plain ways an agent reads the factory tokens. Other forms can still get through, so the narrow token scope is the real guard. See [GitHub tokens](../clients/claude.md#github-tokens). |
| `ask git push` | Every other push asks you first. |
| `ask mcp__work__work_approve` | Approval always asks you. It assumes the MCP server is named `work`. |

`deny` always wins. It also applies to subagents.

## Test it once

Start `claude` in a throwaway git repo and ask it to run these. You should see:

1. `git push origin main` → denied.
2. `git -C . push origin main` → denied. If it only asks, the `-C` rule did not match. Tell me.
3. `git push origin some-branch` → asks you.
4. `gh pr merge 1` → denied.
5. Call `work_approve` → asks you.

## Limits

- This is not a wall. A command hidden in `bash -c "..."`, or a python script that writes the file, can go around it.
- In `dontAsk` mode every `ask` becomes a refusal. Do not use that mode with this harness.
- Python outside Docker is blocked by the older hook `hooks/block-host-python.sh`. Register it as a `PreToolUse` hook on `Bash`.
