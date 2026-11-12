# factory box runner

`build.sh` builds one card in a box and pushes its branch. It runs on the Mac.

```sh
factory/box/build.sh 2      # card 2 → branch factory-2
```

## The brief

The brief is the card's approved spec, copied as is to `~/.factory/runs/factory-<n>/brief.md`.
Set `FACTORY_HOME` to use another folder than `~/.factory`.
A spec that goes to a box has a `## Box` section with three lines:

```
repo: owner/name
model: sonnet
test: <command that proves the work>
```

`repo` and `test` are required, and `build.sh` refuses the brief without them.
`model` is `haiku`, `sonnet` or `opus`, and defaults to `sonnet`.
The fixed job ("one commit per task, run the test until it passes, write `~/handoff.md`") is not in the brief.
`build.sh` adds it as a system prompt.

## What happens

Two boxes keep the GitHub token away from the agent.

1. **Guards.** Fewer than `BOX_CAP` factory boxes are running, there is at least `MIN_FREE_GIB` of free disk, and no other build of this card is running.
2. **Box `factory-<n>`.** `build.sh` clones the repo with the GitHub token.
   If `factory-<n>` already exists on GitHub, this is a **fix round**: it clones that branch, and adds `fixes.md` from the run folder to the prompt.
   It sets you as the commit author, and adds a hook that puts Claude as co-author in every commit.
3. **Agent.** `claude -p` runs with the Claude token only, for at most `AGENT_TIMEOUT`.
   It has the tools Bash, Read, Edit, Write, Glob and Grep, and no MCP servers.
   The agent checks its own work and runs the test.
4. **Facts.** `build.sh` checks that there is at least one new commit and no uncommitted change.
   It packs the work into a git bundle and **removes the box**, so nothing the agent started is still running.
5. **Box `factory-<n>-push`.** A fresh box clones the repo with the token, takes in the bundle, rebases onto the default branch, and pushes `refs/heads/factory-<n>`, and nothing else.
   A fix round pushes with `--force-with-lease`, so the push fails if the branch moved on GitHub in the meantime.
6. Both boxes are removed, also on failure.

Both tokens come from the Mac keychain (`factory-github`, `factory-claude`).
They reach a box only through stdin, never argv and never disk.

## The run folder

`~/.factory/runs/factory-<n>/`:

| File | Written by | Holds |
|---|---|---|
| `brief.md` | the main agent | the card's spec |
| `fixes.md` | the review (optional) | what to fix in the next round |
| `agent.jsonl` | `build.sh` | the agent's full transcript, with the Claude token scrubbed |
| `handoff.md` | the agent | what it did and what it did not do; information only, never a gate |
| `work.bundle` | `build.sh` | the agent's commits, so nothing is lost when a build fails |
| `result.json` | `build.sh` | `status` (`ok`, `failed`, `refused`), `reason`, `branch`, `sha` |

## Exit codes

| Code | Means |
|---|---|
| 0 | pushed |
| 1 | the build failed, nothing was pushed, the evidence is kept |
| 2 | refused before any box started: a bad brief, or a guard |

The settings live in [`../base/box.env`](../base/box.env).
