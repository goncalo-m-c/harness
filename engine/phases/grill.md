# Grill
**Goal:** Turn the user's description into a shared understanding of the work, then name the run.
**Use:** skill `grilling`. Follow it as-is.
**Agent:** `main`. The user talks to this window, so no subagent.
**Main does:**
1. Read `{store}/runs/{key}/ticket.md` (the user's first description), and every ticket, doc, and spec the user named.
2. Look up facts yourself. Ask the user only for decisions.
3. Run the grilling rounds until no open branch remains. Where the code lives is one of the branches.
4. Ask the user to confirm the shared understanding.
5. Draft the decisions as markdown. Format: one dated bullet per decision, then an `Open questions` list.
6. Agree with the user on a slug (a few lowercase words joined by `-`, like `net-worth-split`) and the repo for the code. The repo must use the git-wt layout. If it does not, tell the user and stop: setting it up is their call.
7. Call `work_complete` with the markdown as `evidence`, plus `slug` and `repo`. The engine writes decisions.md and sets the branch and worktree. Do not write any file yourself.
**Write:** the engine writes `{store}/runs/{key}/decisions.md` from `evidence`
**Gate:** `grill_done`. decisions.md is not empty, the slug is set, and the repo has a `.bare` folder.
**Never:**
- Never call `work_complete` before the user confirms.
- Never write any file in `{store}`.
- Never edit `{store}/runs/{key}/state.json`.
