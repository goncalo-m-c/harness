# factory box runner

`build.sh` builds one card in a box and pushes its branch. `review.sh` reviews that branch with three reviewers and a vote.
Both run on the Mac.

```sh
factory/box/build.sh 2      # card 2 → branch factory-2
factory/box/review.sh 2     # review factory-2 → verdict.json, and fixes.md when something must change
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
`check-brief.sh <n>` runs the same checks without starting a box. It prints `ok <repo> <model> <test>` or exits 2.
`model` is `haiku`, `sonnet` or `opus`, and defaults to `sonnet`.
The fixed job ("one commit per task, run the test until it passes, write `~/handoff.md`") is not in the brief.
`build.sh` adds it as a system prompt.

## What happens

1. **Guards.** The image exists, fewer than `BOX_CAP` factory boxes exist, and no other run of this card is going.
2. **Clone on the Mac.** The repo is cloned into the run folder, at `work/`.
   If `factory-<n>` already exists on GitHub, this is a **fix round**: it takes that branch, and adds `fixes.md` from the run folder to the prompt.
   It sets you as the commit author, and adds a hook that puts Claude as co-author in every commit.
3. **Agent.** Box `factory-<n>` gets `work/` mounted at `/work`.
   `claude -p` runs there for at most `AGENT_TIMEOUT`, with the tools Bash, Read, Edit, Write, Glob, Grep and Skill, and no MCP servers.
   Before it starts, the skills named in `BUILD_SKILLS` are copied from this repo's `skills/` into the box.
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

## The review

`review.sh <n>` reviews the pushed branch `factory-<n>` in one box, `factory-<n>-review`.

1. **Guards.** As for a build. A build of the same card must not be running, and the branch must be on GitHub.
2. **Clone on the Mac.** The Mac clones the branch into `review-work/` and writes the diff against the default branch, before any box exists.
   The box gets that clone at `/work`, the brief, the diff, the skills in `REVIEW_SKILLS`, and the `factory-reviewer` agent.
   It has no GitHub login, so it cannot push.
3. **Test.** `review.sh` runs the brief's `test` in the box. If it fails, the verdict is **fix** with the test output, and no reviewer runs.
4. **Session.** One `claude -p` session on sonnet only dispatches. It starts three `factory-reviewer` subagents on opus.
   - **Round 1:** each reviewer works alone and writes its findings.
   - **Round 2:** each reviewer votes on the other two reviewers' findings.
   The aspects, file shapes and vote rules are in [`skills/factory-review`](../../skills/factory-review/SKILL.md).
   The six reviewer files come out of the box one by one, by name.
5. **Model guard.** Every message in the transcript is from sonnet or opus, and every reviewer message is from opus.
6. **Count.** [`count.sh`](count.sh) checks all six files again, then decides. A script decides, not a model.
   - A finding with its author and at least one other reviewer agreeing is a **fix**.
   - A finding with only its author is a **note**, and does not block.
   - A withdrawn finding is dropped.
   - A missing or broken file makes the review **broken**. It is never a pass.

[`test-count.sh`](test-count.sh) proves these rules with seeded votes. It needs no box and no model.

The review adds these files to the run folder:

| File | Holds |
|---|---|
| `verdict.json` | `verdict` (`pass`, `fix`, `broken`, `refused`), `reason`, `sha_reviewed`, the test command and exit code, `fixes`, `notes`, `withdrawn`, and the raw reviewer files |
| `fixes.md` | one section per fix, which `build.sh` reads in the next round |
| `diff.patch` | the diff the reviewers read |
| `review.jsonl` | the session transcript, with the Claude token scrubbed |
| `review-test.log` | the output of the brief's test |
| `out/` | the six reviewer files |

Exit 0: pass. Exit 1: fix. Exit 2: broken or refused.

## The loop

`loop.sh <n>` builds and reviews card `<n>` until a review passes, for at most `MAX_ROUNDS` rounds (3).
The main agent runs it through the [`factory`](../../skills/factory/SKILL.md) skill (`/factory <n>`), which also moves the Trello card and opens the draft PR.
A round is one review.

- `rounds.log` gets one line per finished review: `<round> <sha> <pass|fix> <reason>`.
  It is the only round state, so a re-run continues where the last run stopped.
  - If the pushed sha has no line yet, the loop reviews it first.
  - Otherwise it builds.
- It stops at once on a failed build, a broken review, or when the rounds are used up.
  Then it asks you. It never retries by itself.
- `loop.json` holds `status` (`pass` or `stopped`), `reason`, `rounds` and `sha`.

Exit 0: pass. Exit 1: stopped. [`test-loop.sh`](test-loop.sh) proves the loop with a fake build and a fake review.
