# factory box runner

`build.sh` builds one card in a box and pushes its branch. It runs on the Mac.

```sh
factory/box/build.sh 2      # card 2 → branch factory-2
```

## The box

A box is a Docker container from the image `factory-base` ([`factory/base`](../base/README.md)), started fresh for one step and deleted after it.
It runs as the user `agent` with no capabilities, and sees only the one folder mounted at `/work`.
The network is not isolated yet: a box can reach the Mac and the local network, not only the internet.

Build the image once, and again after a change in `factory/base`:

```sh
docker build -t factory-base factory/base
```

The settings live in [`../base/box.env`](../base/box.env) (image, memory, CPUs, flags) and [`box.env`](box.env) (box cap, timeout, commit author).

**The box never talks to GitHub.** The Mac clones and pushes with your own `gh` login.
The only secret in a box is the Claude token, from the keychain item `factory-claude`. It goes in through stdin, never argv and never disk.

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

1. **Guards.** The image exists, fewer than `BOX_CAP` factory boxes exist, and no other run of this card is going.
2. **Clone on the Mac.** The repo is cloned into the run folder, at `work/`.
   If `factory-<n>` already exists on GitHub, this is a **fix round**: it takes that branch, and adds `fixes.md` from the run folder to the prompt.
   It sets you as the commit author, and adds a hook that puts Claude as co-author in every commit.
3. **Agent.** Box `factory-<n>` gets `work/` mounted at `/work`.
   `claude -p` runs there for at most `AGENT_TIMEOUT`, with the tools Bash, Read, Edit, Write, Glob and Grep, and no MCP servers.
   The agent checks its own work and runs the test.
4. **Facts.** There must be at least one new commit and no uncommitted change.
   The box streams the new commits out as a git bundle, and is deleted.
5. **Push from the Mac.** The Mac never runs git in `work/` again, because the agent could have planted hooks or config there.
   It fetches the bundle into a fresh clone and pushes `refs/heads/factory-<n>`, and nothing else.
   **It refuses to push commits that change `.github/`.** GitHub runs workflows from a pushed branch with the repo's secrets, before any review.
   When a card really needs a workflow change, make that change by hand.
   Other CI that runs the repo's own code on every push (for example a test job on all branches) can still run agent code. Run CI only on `main` and on PRs, or keep its secrets in an environment limited to `main`.
   The push is never forced. A fix round only adds commits, so the push fails if the branch moved on GitHub in the meantime.
6. The box, `work/` and the fresh clone are deleted, also on failure.

## The run folder

`~/.factory/runs/factory-<n>/`:

| File | Written by | Holds |
|---|---|---|
| `brief.md` | the main agent | the card's spec |
| `fixes.md` | the review, only on fix | what to fix in the next build round |
| `agent.jsonl` | `build.sh` | the agent's full transcript, with the Claude token scrubbed |
| `handoff.md` | the agent | what it did and what it did not do; information only, never a gate |
| `work.bundle` | `build.sh` | the agent's commits, so nothing is lost when a push fails |
| `result.json` | `build.sh` | `status` (`ok`, `failed`, `refused`), `reason`, `branch`, `sha` |

## Exit codes

| Code | Means |
|---|---|
| 0 | pushed |
| 1 | the build failed, nothing was pushed, the evidence is kept |
| 2 | refused before any work started: a bad brief, or a guard |
