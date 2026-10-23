# Python rules (PY)

Applies to `*.py` / `*.pyi`. **All rules below are hard for new or changed code** in the diff (not for untouched legacy).

## PY-CONVENTIONS (hard)

Follow `~/.agents/rules/code-style.md` for Python in the diff:

- **Layout:** Callers above callees; entry point or public contract first, private helpers below. Listeners/plugins/adapters lead with the public surface, then helpers.
- **Naming:** snake_case functions and variables, PascalCase classes. Descriptive names — no `df`, `data`, `tmp`, `res`. Value functions named for what they return; side-effect functions named for what they do. `get_`/`set_` only for real accessors.
- **Functions:** Small, one job (~20 lines as a guide). No dead code, commented-out blocks, or unused imports in new code.
- **Comments:** Explain why, not what; keep inline comments short (prefer docs for long explanations).
- **Patterns:** If the diff introduces a named design pattern, the PR description (or, before a PR exists, the commit messages or repo docs) must name it (see CM-PATTERN in common rules).

Framework registration order (`@task`, fixtures, etc.) follows the framework; do not reorder those for step-down.

## Other Python checks

| ID | Rule | Sev |
| --- | --- | --- |
| PY-TYPES | Annotate params and returns on new/changed functions | hard |
| PY-PATH | `pathlib.Path`, not `os.path` | hard |
| PY-ENTRY | Scripts use `if __name__ == "__main__":` | hard |
| PY-ERR | No bare `except:` or swallowed exceptions | hard |
| PY-VALIDATE | Validate external input at boundaries | hard |

Skip PY-TYPES / naming duplicates when repo `ruff`/`mypy` already enforces the same rule.
