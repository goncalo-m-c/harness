---
paths:
  - "**/*.py"
  - "**/*.pyi"
---

# Python rules (PY)

Follow these rules when you write Python. Reviewers check them on new or changed code only.
The repo's own documented standards win over these rules.

## PY-RUFF (hard): run ruff before each commit

Ruff checks naming case, type annotations, pathlib, bare `except`, unused imports and commented-out code.
Run it in Docker. It uses the repo's ruff config, or the global one when the repo has none:

    docker run --rm -v "$PWD:$PWD" -w "$PWD" \
      -v "$HOME/.config/ruff/ruff.toml:/cfg/ruff/ruff.toml:ro" -e XDG_CONFIG_HOME=/cfg \
      ghcr.io/astral-sh/ruff:0.17.1 check <the .py files you changed>

Fix every error in lines you added or changed, before you commit. Leave old code alone.
Reviewers run the same command on the diff's .py files. Each error in an added or changed line is a hard finding.

## Rules ruff cannot check

**PY-ORDER (hard): callers above callees.** The entry point or public contract comes first. Helpers come below, in the order they are called.
Framework registration order (`@task`, fixtures) follows the framework.

```python
def sync_users():             # good: the entry point first
    for user in fetch_users():
        save_user(user)


def fetch_users(): ...        # then the helpers, in the order they are called


def save_user(user): ...
```

**PY-NAME (hard): a value function is named for what it returns. An action function is named for what it does.**
`get_`/`set_` only for real accessors. No vague names: `data`, `tmp`, `res`, `df`.

```python
def task_key(task): ...        # good: returns a value
def stop_and_log(job): ...     # good: has a side effect
def get_task_key(task): ...    # bad: get_ on a computed value
def process(data): ...         # bad: vague verb, vague name
```

**PY-SIZE (judgement): one job per function.** Split past about 20 lines, or when the honest name needs "and".

**PY-COMMENT (judgement): comments explain why, not what.** At most two lines in code. Longer text goes in docs.

**PY-VALIDATE (hard): validate external input at the boundary**: requests, files, env vars, CLI args.

**PY-ENTRY (hard): scripts use `if __name__ == "__main__":`.**
