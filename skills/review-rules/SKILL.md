---
name: review-rules
description: >-
  Language rules (Python call order, naming, ruff; Bash; Terraform). Claude Code also loads
  python.md by itself when an agent works on a .py file. Load for Standards-axis review in
  /work, code-review, and /review.
---

# Review rules

Library for the **Standards** axis. Use with `~/Projects/.agents/skills/code-review/SKILL.md`; does not replace it.

## Steps

1. Take the worktree and diff base from the caller.
2. Run `bash ~/.agents/skills/review-rules/scripts/select-rules.sh <worktree> <base>`. It prints rule files (`common.md` plus languages in the diff).
3. Read each printed file. Apply language files only to matching paths.
4. Load repo standards (`AGENTS.md`, `CODING_STANDARDS.md`, `GOLDEN_PATH.md`, linter config). Repo docs win on conflict.

## Precedence

Repo documented standard > rules here > smell baseline (always judgement).

## Scope

- Flag only code **added or moved** in the diff.
- Run the linter command a rule file names (like PY-RUFF). Report each linter error on an added or moved line once, under that rule. Do not report it again under another rule.
- Findings: `[RULE-ID] path:line — what, fix`. Tag `hard` or `judgement` as in the rule file.
- End with `hard N · judgement M`.
