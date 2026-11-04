---
name: work
description: Run one piece of work through grill, spec, implement, review and PR (with CI), with an engine that owns state and gates. Args are a description of the work, in the user's words, or KEY alone to resume a run.
disable-model-invocation: true
---

# Work

Args: a description of the work, like `split net worth between me and my partner`, or `KEY` alone to resume a run.
The user may also name a ticket key they already have (from Jira, for example).
The `work` MCP server owns the state and the gates. You own the conversation and the work.

Rules:
1. With `KEY` alone, call `work_next(key)`. Otherwise call `work_start(description)`. It creates nothing and returns the models and the key prefixes in use. Show both to the user. Ask them to confirm or change the models, and to pick a prefix (or give their key). Then call `work_start` again with `description`, `prefix` (or `key`) and `models={agent: model}` for every agent. The engine picks the key.
2. Do exactly what `work_next` returns. Nothing more, nothing less.
3. When the phase output is ready, call `work_complete(key, evidence)`. In grill, `evidence` is the decisions markdown, and you also pass `slug` and `repo`: the engine writes the file and names the branch. In review, pass no evidence: the reviewers write their own reports and the engine reads them. Write nothing in `{store}` yourself.
4. If the gate fails, fix the reasons and call `work_complete` again.
5. When approval is pending, ask the user and wait.
6. Never call `work_approve` without the user's explicit yes in this chat.
7. Never edit anything under `{store}/runs/*/state.json`.
8. Never skip a phase.
9. Any user request that needs running commands, reading more than a couple of files, or editing goes through `work_task(key, request, kind)`. Use kind `edit` or `investigate`. The main window only relays summaries.
10. Never change a model without the user's word. Never dispatch a subagent without the model from `work_next` or `work_task`. Pass it as the Agent tool's `model` parameter.
11. Save a checkpoint with `work_checkpoint(key, summary)` when the engine says so, or when the user asks. The new checkpoint replaces the old one, so it covers the whole run. Use three short lists: `Done`, `Decided`, `Still open`. Name files and commits, not chat. A fresh session must be able to continue from it alone.
12. When the user asks for a checkpoint to clear the session, save it, then tell them to run `/clear` and `/work KEY`.
