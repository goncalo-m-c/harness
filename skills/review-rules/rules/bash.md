# Bash rules (BASH)

- **BASH-STRICT** (hard): `#!/usr/bin/env bash` and `set -euo pipefail`.
- **BASH-FUNC** (judgement): Non-trivial logic in named functions; `main` last.
- **BASH-QUOTE** (hard): Quote variables that may contain spaces.
- **BASH-STDERR** (hard): Errors to stderr; prefer `printf` over `echo`.
- **BASH-LS** (hard): No `ls` in scripts; use globs or `find`.
