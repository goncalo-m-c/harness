# Grill
**Goal:** Reach a shared understanding of the ticket with the user.
**Use:** skill `grilling`. Follow it as-is.
**Agent:** `main`. The user talks to this window, so no subagent.
**Main does:**
1. Read every ticket, doc, and spec the user named.
2. Look up facts yourself. Ask the user only for decisions.
3. Run the grilling rounds until no open branch remains.
4. Ask the user to confirm the shared understanding.
5. Draft the decisions as markdown. Format: one dated bullet per decision, then an `Open questions` list.
6. Call `work_complete` with that markdown as `evidence`. The engine writes decisions.md. Do not write any file yourself.
**Write:** the engine writes `{store}/runs/{key}/decisions.md` from `evidence`
**Gate:** `decisions_written`. The file exists and is not empty.
**Never:**
- Never call `work_complete` before the user confirms.
- Never write any file in `{store}`.
- Never edit `{store}/runs/{key}/state.json`.
