# Extending

Most changes touch two or three files. What each change needs before it works:

- **A phase file** (`engine/phases/*.md`): nothing. The engine reads it at each call.
- **`pipeline.yaml` or a Python file:** restart Claude Code. It starts a new engine with each session.
- **The [`Dockerfile`](../engine/Dockerfile):** rebuild the image, then restart Claude Code.
- **A new agent or skill:** restart Claude Code.

## Add a phase

1. **Add an entry** to [`engine/pipeline.yaml`](../engine/pipeline.yaml), at the right place in the list:

   ```yaml
   - name: docs
     agent: work-docs-writer      # or `main` when the chat agent does it with you
     tier: standard
     instructions: phases/docs.md
     rules: [communication]       # optional: files from rules/ to paste in
     gate: docs_written
     needs_approval: false        # true: the user must approve before the next phase
   ```

2. **Write `engine/phases/docs.md`.** Copy the sections of an existing phase file.
   For a subagent phase, keep these three headings exactly. The engine splits the file on them:
   - `**Subagent does:**` is the prompt for the subagent.
   - `**Main does:**` is the steps for the chat agent.
   - `**Write:**` starts the rest of the page.

   These placeholders are filled in for each run: `{key}`, `{change}`, `{worktree}`, `{branch}`, `{store}`, `{harness}`.

3. **Add the agent** as `agents/work-docs-writer.md`, and link it into `~/.claude/agents/`.

4. **Add the gate** (see below).

## Add a gate

A gate is a function in [`engine/gates.py`](../engine/gates.py). It gets the run state and returns two things: did it pass, and the reasons if not.

```python
def docs_written(state):
    path = Path(state["worktree"]) / "docs"
    ok = path.is_dir()
    return ok, [] if ok else [f"{path} is missing"]
```

Add it to the `GATES` table at the bottom of the file, under the same name as in `pipeline.yaml`.
Write the reasons so that the agent knows what to fix.
Add a test in [`engine/test_gates.py`](../engine/test_gates.py).

## Add a language

See [Rules](5-rules.md#adding-a-language). To also check it in the gates:

1. Add the linter to the [`Dockerfile`](../engine/Dockerfile), pinned to one version, and rebuild the image.
2. In `gates.py`, run it the way `ruff_problems` runs ruff: only on lines the branch added.

## Add a tool other than Claude Code

1. Write `clients/<tool>.md`: how to connect the engine, link the skills and agents, and add the safety rules.
2. Add a model table for the tool under `client_models` in `pipeline.yaml`.
3. Start the engine with `WORK_CLIENT=<tool>`, so it uses that table.

Next: back to the [start](README.md), or the [glossary](glossary.md).
