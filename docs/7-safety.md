# Safety

Some protections are **enforced**: code or Claude Code stops the action.
Others are **instructions**: the agent is told not to do something, and nothing checks it.
Know which is which.

## Enforced

| What | How |
|---|---|
| Skip a phase | The engine moves on only when the gate passes. See [Phases](3-phases.md#gates). |
| Skip an approval | The engine waits for `work_approve`. Claude Code asks you each time it is called. |
| Change the run state | A permission rule denies edits to `runs/**/state.json`. |
| Merge a PR, or mark it ready | A permission rule denies `gh pr merge` and `gh pr ready`. |
| Push to `main` or `master` | A permission rule denies it. |
| Any other push | A permission rule asks you first. |
| New Python lines that break ruff | The implement and review gates run ruff. |
| Python on your own machine | The optional hook (see below) blocks it outside Docker. |

The permission rules are in [`settings/permissions.example.json`](../settings/permissions.example.json).
You copy them into `~/.claude/settings.json`. They apply to the chat agent and to every subagent.
`deny` always wins over `ask` and `allow`. [`settings/README.md`](../settings/README.md) has a short test for them.

The hook is [`hooks/block-host-python.sh`](../hooks/block-host-python.sh).
It blocks `python`, `pip`, `uv` and `pytest`, and allows them inside `docker run` or `docker exec`.

## Only instructions

The agents are told these things. Nothing checks them:

- The chat agent hands every code change to a subagent.
- No agent edits or commits in your repo's `main` folder.
- The chat agent writes nothing in the store.
- The reviewers write only their own report. The chat agent never writes a report.
- `work-explorer` changes nothing. Its `readonly: true` line does not stop it.
- The agent asks you to confirm the decisions in grill, and waits for your go after the hunk review.

These rules usually hold. But if one breaks, nothing stops it. Watch for them.

## Weak spots

- **The grill gate is weak.** It passes on any decisions text that is not empty. It checks the slug and the repo, not the decisions.
- **The review reports are not protected.** An agent could write "No findings." itself, and the review gate would pass.
- **Permission rules can be bypassed.** A command hidden in `bash -c "..."`, or a script that writes a file, gets around them.
- **`dontAsk` mode breaks the approvals.** In that mode every `ask` becomes a refusal. Do not use it with this harness.
- **Gates check facts, not quality.** A review with no `hard` finding can still miss a bug. Read the code yourself in hunk.

## Never

- Never add `work_approve` to an allow list.

Next: [Extending](8-extending.md).
