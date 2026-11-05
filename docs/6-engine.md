# Engine

The engine is a small MCP server in [`engine/`](../engine/). It runs in Docker.
It owns the state of each run and runs the gates. It never writes code.
For exact install details, see [`engine/README.md`](../engine/README.md).

## The six tools

The chat agent talks to the engine only through these tools:

| Tool | What it does |
|---|---|
| `work_start(description, prefix or key, models)` | Creates a run with the next free key for the prefix, or with your key. Without `models`, it creates nothing and returns the model table and the prefixes in use. |
| `work_next(key)` | Returns the current phase, its instructions, its gate and the latest checkpoint. |
| `work_complete(key, evidence)` | Runs the gate of the current phase. On a pass, the run moves on or waits for approval. In grill it also takes `slug` and `repo`, and names the branch and the worktree. |
| `work_approve(key)` | Your approval. It works only when an approval is waiting. |
| `work_task(key, request, kind)` | Logs an extra request and returns the prompt for the subagent. The phase stays the same. |
| `work_checkpoint(key, summary)` | Saves the latest checkpoint. |

## How a phase runs

1. The agent calls `work_next`. The engine reads the phase file in `engine/phases/` and fills in the paths for this run.
2. If a subagent does the phase, the engine returns a ready prompt for it, and the model to use.
3. The agent sends the prompt to the subagent and waits for its report.
4. The agent calls `work_complete`. The engine runs the gate.
5. Gate passed: the run goes to the next phase, or waits for your approval. Gate failed: the reasons go back to the agent.

## The store

The store is a folder you choose, for example `~/Projects/work-store`. It holds all runs and specs:

```
work-store/
  runs/<KEY>/
    state.json        phase, status, branch, models, history   (only the engine writes it)
    ticket.md         your first description of the work       (the engine writes it)
    decisions.md      the decisions from grill                 (the engine writes it)
    checkpoint.md     the latest checkpoint                    (the engine writes it)
    tasks.md          every extra request                      (the engine writes it)
    reviews/spec.md   the spec review                          (the reviewer writes it)
    reviews/standards.md  the standards review                 (the reviewer writes it)
    ci/latest.json    the raw CI result                        (work-pr writes it)
  openspec/changes/<slug>/
    proposal.md, design.md, tasks.md, specs/                   (the spec writer writes them;
                                                               the implementer ticks tasks.md)
```

The chat agent is told to write nothing in the store. It passes text to the engine, and the engine writes the file.
A permission rule protects only `state.json`. See [Safety](7-safety.md).

## The state

`state.json` holds the phase and the status. The status is one of `in_progress`, `awaiting_approval` or `done`.
It also holds a `history` list: one line for each event, with a time.

## Refusals

When the engine says no, it writes a line to `history`:

- `gate_failed`: the gate did not pass. This is often normal, for example a review with `hard` findings.
- `complete_refused`: the agent tried to finish while an approval was waiting, or after the run was done.
- `approve_refused`: an approval was called, but nothing was waiting.

Many refusals of the other two kinds mean an agent tries to skip steps. Count all refusals for one run:

    jq '[.history[] | select(.event | test("failed|refused"))] | length' runs/<KEY>/state.json

## Where the code is

Read the files in this order:

1. [`pipeline.yaml`](../engine/pipeline.yaml): the phases, agents, gates and approvals.
2. [`phases/*.md`](../engine/phases/): what the agents do in each phase.
3. [`engine.py`](../engine/engine.py): the six tools.
4. `state.py`, `models.py`, `dispatch.py`, `gates.py`: what the tools call.

The tests are in `test_gates.py`. Run them in Docker:

    docker run --rm -v "$ROOT:$ROOT" -e WORK_STORE=/tmp/store \
      -w "$HARNESS/engine" work-engine:0.1.0 python -m unittest test_gates -v

`ROOT` and `HARNESS` are the paths from [`clients/claude.md`](../clients/claude.md).
Mount all of `ROOT`, not only the harness. A git worktree keeps its git data in the main checkout.

Next: [Safety](7-safety.md).
