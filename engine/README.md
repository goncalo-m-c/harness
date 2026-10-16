# work engine

The engine owns run state and gates. The chat agent owns the conversation.

```
 you <-> agent chat (/work2 KEY SLUG REPO)
              |  MCP over stdio (docker run -i)
              v
   work_start | work_next | work_complete | work_approve | work_task  <- engine.py
              |
     +--------+-----------------+
     v                          v
 pipeline.yaml + phases/*.md   GATES (code)
 (the map, the instructions)   decisions, openspec, git, review, push, ci
              |
              v
   runs/<KEY>/state.json  (atomic write)  +  decisions.md, reviews/NN.md
```

## Build the image

The image holds only the runtime. `engine.py` is mounted, so edits need no rebuild.

    docker build -t work-engine:poc <harness>/engine

## MCP entry

Replace `<root>` with the folder that holds the harness and the store.
`WORK_STORE` is required. The engine does not start without it.

    "work": {
      "command": "docker",
      "args": ["run", "-i", "--rm", "-v", "<root>:<root>",
               "-e", "WORK_STORE=<root>/work-store",
               "work-engine:poc", "python", "<root>/harness/engine/engine.py"]
    }

Do not auto-approve `work_approve`. The client must ask you each time.

## How to read this folder

1. `pipeline.yaml`: the phases, gates and approvals.
2. `phases/*.md`: what the agent does in each phase.
3. `engine.py`: the 5 tools (the public contract).
4. `state.py`, `models.py`, `dispatch.py`, `gates.py`: what the tools call, in that order.

## Models

`pipeline.yaml` lists `allowed_models` by vendor and a default model per subagent.
`work_start` without `models` creates nothing and returns the table. The user confirms it.
`work_start` with `models={agent: model}` validates it and stores it in `state.json`.
A reviewer must not share a vendor with the implementer.
Every dispatch block names the model. The main window passes it as the Task tool's `model`.

## Files the engine writes

The main window writes nothing in the store. The `work2` skill forbids it.
`work_complete(key, evidence)` in `grill` writes `runs/<KEY>/decisions.md` from `evidence` (an empty `evidence` keeps an existing file).
In `review` it writes the next `runs/<KEY>/reviews/NN.md` from `evidence`. Subagents write their own files (spec, `ci/`).
