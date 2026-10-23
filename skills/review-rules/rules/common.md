# Common rules (CM)

- **CM-NAME** (hard): Names describe values or actions; no vague `data`, `tmp`, `res`.
- **CM-PATTERN** (hard): Named design pattern in new code must be stated in the PR description, or, when no PR exists yet, in the commit messages or the repo docs.
- **CM-SIZE** (judgement): One job per function; split past ~20 lines or honest “and” in the name.
- **CM-DEAD** (hard): No dead code, commented-out blocks, or unused imports.
- **CM-COMMENT** (judgement): Comments explain why; at most two lines in code.
- **CM-NAMED-COND** (judgement): Long boolean chains get a named predicate.
- **CM-ERR** (hard): No silent failures; log or surface errors.
- **CM-SECRETS** (hard): No secrets or account IDs in source.
