# factory box runner

`build.sh` builds one card in a box and pushes its branch. `review.sh` reviews that branch with three reviewers and a vote.
Both run on the Mac.

```sh
factory/box/build.sh 2      # card 2 → branch factory-2
factory/box/review.sh 2     # review factory-2 → verdict.json, and fixes.md when something must change
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
`check-brief.sh <n>` runs the same checks without starting a box. It prints `ok <repo> <model> <test>` or exits 2.
`model` is `haiku`, `sonnet` or `opus`, and defaults to `sonnet`.
The fixed job ("one commit per task, run the test until it passes, write `~/handoff.md`") is not in the brief.
`build.sh` adds it as a system prompt.

## What happens

Two boxes keep the GitHub token away from the agent.

1. **Guards.** Fewer than `BOX_CAP` factory boxes are running, there is at least `MIN_FREE_GIB` of free disk, and no other build of this card is running.
2. **Box `factory-<n>`.** `build.sh` clones the repo with the GitHub token.
   If `factory-<n>` already exists on GitHub, this is a **fix round**: it clones that branch, and adds `fixes.md` from the run folder to the prompt.
   It sets you as the commit author, and adds a hook that puts Claude as co-author in every commit.
   It copies the skills named in `BUILD_SKILLS` from this repo's `skills/` into the box.
3. **Agent.** `claude -p` runs with the Claude token only, for at most `AGENT_TIMEOUT`.
   It has the tools Bash, Read, Edit, Write, Glob, Grep and Skill, and no MCP servers.
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
| `fixes.md` | `review.sh`, only on fix | what to fix in the next build round |
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

## The review

`review.sh <n>` reviews the pushed branch `factory-<n>` in one box, `factory-<n>-review`.

1. **Guards.** As for a build. A build of the same card must not be running, and the branch must be on GitHub.
2. **Clone.** This is the only step with the GitHub token. The clone's push URL is set to `none`, so the box cannot push.
   The box gets the brief, the diff against the default branch, the skills in `REVIEW_SKILLS`, and the `factory-reviewer` agent.
3. **Test.** `review.sh` runs the brief's `test` in the box. If it fails, the verdict is **fix** with the test output, and no reviewer runs.
4. **Session.** One `claude -p` session on sonnet only dispatches. It starts three `factory-reviewer` subagents on opus.
   - **Round 1:** each reviewer works alone and writes its findings.
   - **Round 2:** each reviewer votes on the other two reviewers' findings.
   The aspects, file shapes and vote rules are in [`skills/factory-review`](../../skills/factory-review/SKILL.md).
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
| `review.jsonl` | the session transcript, with the Claude token scrubbed |
| `review-test.log` | the output of the brief's test |
| `out/` | the six reviewer files |

Exit 0: pass. Exit 1: fix. Exit 2: broken or refused.

## The loop

`loop.sh <n>` builds and reviews card `<n>` until a review passes, for at most `MAX_ROUNDS` rounds (3).
A round is one review.

- `rounds.log` gets one line per finished review: `<round> <sha> <pass|fix> <reason>`.
  It is the only round state, so a re-run continues where the last run stopped.
  - If the pushed sha has no line yet, the loop reviews it first.
  - Otherwise it builds.
- It stops at once on a failed build, a broken review, or when the rounds are used up.
  Then it asks you. It never retries by itself.
- `loop.json` holds `status` (`pass` or `stopped`), `reason`, `rounds` and `sha`.

Exit 0: pass. Exit 1: stopped. [`test-loop.sh`](test-loop.sh) proves the loop with a fake build and a fake review.
