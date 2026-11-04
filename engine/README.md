# work engine

The engine owns run state and gates. The chat agent owns the conversation.

```
 you <-> agent chat (/work KEY SLUG REPO)
              |  MCP over stdio (docker run -i)
              v
   work_start | work_next | work_complete | work_approve | work_task | work_checkpoint  <- engine.py
              |
     +--------+-----------------+
     v                          v
 pipeline.yaml + phases/*.md   GATES (code)
 (the map, the instructions)   decisions, openspec, git, review, push, ci
              |
              v
   runs/<KEY>/state.json  (atomic write)  +  decisions.md, reviews/*.md
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
3. `engine.py`: the 6 tools (the public contract).
4. `state.py`, `models.py`, `dispatch.py`, `gates.py`: what the tools call, in that order.

## Models

`pipeline.yaml` gives each subagent a tier (fast, standard or strong). `client_models` turns a tier into a model name.
`WORK_CLIENT` picks the table. The default is `claude` (haiku, sonnet, opus).
`work_start` without `models` creates nothing and returns the table. The user confirms it.
`work_start` with `models={agent: model}` validates it and stores it in `state.json`.
A reviewer must not use the same model as the implementer.
Every dispatch block names the model. The main window passes it as the Agent tool's `model`.

## Rules

A phase in `pipeline.yaml` can list `rules: [git, code-style]`. These are files in `../rules/`.
`work_next` pastes their text into the instructions, so the agent does not need to find them.
In a subagent phase the text goes inside the subagent prompt, because subagents do not see the main chat.
`work_task` (kind `edit`) gets the rules of the implement phase.

## Files the engine writes

The main window writes nothing in the store. The `work` skill forbids it.
`work_complete(key, evidence)` in `grill` writes `runs/<KEY>/decisions.md` from `evidence` (an empty `evidence` keeps an existing file).
`work_checkpoint(key, summary)` writes `runs/<KEY>/checkpoint.md`. It replaces the previous one.
Subagents write their own files: the spec, the review reports (`reviews/spec.md`, `reviews/standards.md`) and `ci/`.
The review gate reads the two reports and counts the `- hard:` lines itself. A report must be newer than the last commit.

## Checkpoints

Long talks fill the context and make the results worse. A checkpoint lets you start a fresh session.
The engine asks the main window to save one on every gate pass, and after every 5 `work_task` calls since the last one.
You can also ask for one. Then run `/clear` and `/work KEY`. `work_next` shows the latest checkpoint to the new session.

## Skip attempts

Each time an agent tries to skip, the engine adds a line to `history` in `state.json`:
`gate_failed` (the gate did not pass), `complete_refused` (finish while approval is pending or the run is done) and `approve_refused` (approve when nothing waits).
The `detail` field says why. Count them for one run:

    jq '[.history[] | select(.event | test("failed|refused"))] | length' runs/<KEY>/state.json
