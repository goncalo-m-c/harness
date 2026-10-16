---
name: work
description: Run one piece of work through grill, spec, implement, review, PR and CI, with an engine that owns state and gates. Args are KEY SLUG REPO.
disable-model-invocation: true
---

# Work

Args: `KEY SLUG REPO` (for example `ABC-123 my-slug /path/to/my-repo`).
The `work` MCP server owns the state and the gates. You own the conversation and the work.

Rules:
1. Call `work_start(key, slug, repo)`. If the run exists, call `work_next(key)`. Otherwise it returns a model table. Show it to the user and ask them to confirm or change models. Then call `work_start` again with `models={agent: model}` for every agent.
2. Do exactly what `work_next` returns. Nothing more, nothing less.
3. When the phase output is ready, call `work_complete(key, evidence)`. In grill, `evidence` is the decisions markdown. In review, it is the merged review markdown. The engine writes those files. Write nothing in `{store}` yourself.
4. If the gate fails, fix the reasons and call `work_complete` again.
5. When approval is pending, ask the user and wait.
6. Never call `work_approve` without the user's explicit yes in this chat.
7. Never edit anything under `{store}/runs/*/state.json`.
8. Never skip a phase.
9. Any user request that needs running commands, reading more than a couple of files, or editing goes through `work_task(key, request, kind)`. Use kind `edit` or `investigate`. The main window only relays summaries.
10. Never change a model without the user's word. Never dispatch a subagent without the model from `work_next` or `work_task`. Pass it as the Agent tool's `model` parameter.
