# Daily use

## Extra requests during a phase

You will often want something that is not in the plan: a quick question, a small fix, a fact from the docs.
Just ask in the chat. A simple question the agent answers itself.
If the request needs commands, more than a couple of files, or any edit, the agent sends it to the engine with `work_task`. There are two kinds:

- **investigate**: `work-explorer` looks something up and returns a short answer. It is told to change nothing.
- **edit**: `work-implementer` makes the change in the worktree and commits it.

The phase does not change. The engine writes each request to `runs/<KEY>/tasks.md`, so you can see them later.
The chat agent shows you only a short summary, so your chat stays small.

## Checkpoints and fresh sessions

A long chat makes the agent's answers worse. A checkpoint lets you start again with a clean chat.

A checkpoint is a short note with three lists: **Done**, **Decided** and **Still open**.
The engine saves it in `runs/<KEY>/checkpoint.md`. A new checkpoint replaces the old one, so it always covers the whole run.

The engine asks the agent to save a checkpoint:
- each time a gate passes, and
- after every 5 extra requests since the last checkpoint.

You can also ask for one at any time. To start fresh:

1. Say "checkpoint".
2. Type `/clear`.
3. Type `/work ABC-123`.

The new chat gets the current phase and the latest checkpoint from the engine. It continues from there.

## Reviewing the code yourself

At the end of the implement phase, the commits open in hunk, in a new tab.

- **↑ ↓** move between commits. **Enter** opens a diff.
- **q** goes back. **q** again closes hunk.
- **r** refreshes. New commits do not appear on their own.

Look now, before the review. Your own changes then come before the two reviewers run, not after.
This saves review rounds, because every new commit makes both reviewers run again.

## When CI is red

The `work-pr` agent waits for the CI checks. If one fails, it reads the end of the failing log.
The chat agent shows you the failing check and the likely cause, and asks you for a yes.
With your yes, the implementer fixes it. Then `work-pr` pushes and waits again.
Claude Code asks you once more when the push happens.

## When CI takes long

`work-pr` waits about 20 minutes. Then it stops and reports `still running`.
The phase stays open. Ask the agent to check CI again when you want.

## Resuming a run

Run `/work KEY`. The engine knows the phase. If an approval is waiting, the agent asks you for it first.

To see where all your runs are:

    jq -r '"\(.key)  \(.phase) / \(.status)"' $STORE/runs/*/state.json

## When things go wrong

**The implementer reports `blocked`.** It could not finish, and its report says why.
The agent tells you the reason. Decide the next step together, then send it as an extra request.

**A gate keeps failing.** Read the reasons. The engine writes each failed gate to `history` in `state.json`.
If the reason is wrong, the gate may have a bug. Fix it in `engine/gates.py`.

**The spec turns out to be wrong.** A run cannot go back a phase. Two ways out:
- Fix the spec with an extra edit request. The spec writer's files are plain text in `openspec/changes/<slug>/`.
- Start over. Delete `runs/<KEY>/` and `openspec/changes/<slug>/` in the store yourself. Then run `/work KEY SLUG REPO` again.
  The worktree and its commits stay. Delete them with `git-wt` if you do not need them.

Next: [Rules](5-rules.md).
