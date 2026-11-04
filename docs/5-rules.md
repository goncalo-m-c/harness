# Rules

Rules keep the agents consistent, so you do not correct the same things again and again.
Rules also cost context: every rule an agent reads takes space in its memory.
So the harness loads each rule only where it is needed.

## Three ways a rule reaches an agent

**1. Pasted into the prompt.** A phase in `pipeline.yaml` can list files from [`rules/`](../rules/).
The engine pastes their text into the instructions for that phase.

| File | What it says | Pasted into |
|---|---|---|
| `code-style.md` | general code rules that fit every language | implement, and every extra edit |
| `commands.md` | run python and similar tools only in Docker | implement, pr |
| `git.md` | branches, commit messages, draft PRs | implement, pr |
| `communication.md` | write in short, plain sentences | grill |
| `subagents.md` | what the chat agent hands to subagents | grill |

**2. Loaded by file type.** A language rule file, like [`python.md`](../skills/review-rules/rules/python.md), starts with a `paths:` list:

```
---
paths:
  - "**/*.py"
---
```

It is linked into `~/.claude/rules/`. Claude Code loads it when an agent reads a file that matches the list.
This works in your chat and in subagents, inside a run or not.
If no agent touches Python, the Python rules cost nothing.

There is one gap. Claude Code does not load the rule when an agent *creates* a new file.
So `code-style.md` tells the implementer to read its language's rule file before it writes code.

**3. Checked by a linter in the gate.** A linter checks some rules better than any agent can.
For Python, [ruff](https://docs.astral.sh/ruff/) checks names, type hints, `pathlib`, bare `except`, unused imports and commented-out code.
The implement gate and the review gate run ruff themselves. So an agent cannot skip it.

## One rule list for the writer and the reviewer

The implementer and the standards reviewer read the same language file.
So the code is written and checked against the same rules.

## Only new code counts

The ruff gate counts errors only on lines the branch added.
Old code in a changed file does not block the gate, and agents leave it alone.

## The ruff config

The global config is [`settings/ruff/ruff.toml`](../settings/ruff/ruff.toml). It is linked to `~/.config/ruff/ruff.toml`.
Ruff uses it only in repos with no ruff config of their own. A repo config always wins.

## Adding a rule

- **Can a linter check it?** Then add it to the linter config, not to a rule file. A linter rule costs no context.
- **Otherwise,** add one line to the language file, with a bad and a good example.
- **Keep each file short:** about 10 rules. A new rule should replace a weaker one or merge into one.
- **Add a rule after the second time** you correct the same thing. One correction can be chance.

## Adding a language

1. Write `skills/review-rules/rules/<language>.md`, with a `paths:` list at the top.
2. Link it: `ln -sfn "$HARNESS/skills/review-rules/rules/<language>.md" ~/.claude/rules/<language>.md`.
3. Make sure the review finds it: [`select-rules.sh`](../skills/review-rules/scripts/select-rules.sh) maps file endings to rule files.
4. Optional: add a linter for it to the engine image and to the gates. See [Extending](8-extending.md).

Next: [Engine](6-engine.md).
