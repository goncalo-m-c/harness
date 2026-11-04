# What it is

## The problems

An AI coding agent can write good code. But on a real ticket, four things often go wrong:

1. **It skips steps.** It starts coding before you agree on what to build. Or it opens a PR without a review.
2. **The chat gets too long.** Every question and every small fix stays in the chat. A long chat makes the agent's answers worse.
3. **The style drifts.** You correct the same things again and again: names, function order, type hints.
4. **You lose track.** After a break, you do not know which step the work is in, or what is still open.

## The idea

The harness splits the work into fixed steps, called **phases**:

```
grill → spec → (you approve) → implement → review → (you approve the push) → PR and CI
```

A small program, the **engine**, owns the state of the work. It saves the state in a file.
At the end of each phase, the engine runs a **gate**: a check written in code.
The agent moves to the next phase only when the gate passes.
So the agent cannot skip a phase. Most gates look at real files, so the agent cannot just claim the work is done.

## Words you will see

- **Grill**: the first phase. The agent asks you questions until you agree on what to build.
- **Spec**: the written plan for the work: a proposal, a design and a task list.
- **Worktree**: a separate folder for the ticket's branch, next to your repo's `main` folder. All code changes happen there.
- **Store**: one folder that holds the state, the decisions, the specs and the reviews of all your runs.
- **Checkpoint**: a short note of what is done and still open. A fresh chat can continue from it.

More words are in the [glossary](glossary.md).

```
 you  <->  chat agent  (/work KEY SLUG REPO)
                |
                |  asks the engine what to do next, and reports when a phase is done
                v
             engine  ---- runs the gate ---->  pass: next phase
                |                              fail: the reasons go back to the agent
                v
           state.json, decisions.md, spec, reviews ...  (files in the store)
```

## Who does what

- **You** make the decisions and approve the important steps.
- **The chat agent** talks with you. It is told to hand every code change to a subagent. This is an instruction, not a check.
- **Subagents** do the heavy work: write the spec, write the code, review it, open the PR.
  Each one starts with a clean context, so your chat stays short.
- **The engine** keeps the state and runs the gates. It never writes code.

## How it solves the four problems

| Problem | What the harness does |
|---|---|
| Skipped steps | Gates in code. Two steps also need your approval. |
| Long chat | Subagents do the heavy work. Checkpoints let you start a fresh chat. |
| Style drift | Rule files load when an agent works on Python. Ruff checks new Python lines in the gate. |
| Lost track | The engine saves the phase and a checkpoint. `/work KEY` resumes the run. |

Next: [First run](2-first-run.md).
