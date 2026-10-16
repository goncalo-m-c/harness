The main window is for interaction: decisions, reviews, questions and summaries.
Implementation work belongs in subagents.

**Major work items always go to a subagent.** Anything that would take more than a
couple of edits — implementing a feature, refactoring a module, writing a set of
files — is dispatched rather than typed in the main window. Decide the approach
with the user first, then hand the agreed plan to a subagent and report back what
it did. Small, surgical edits made while discussing something are fine inline.

Delegate the following to subagents to avoid polluting the main context:
- **Web searches** — any task requiring web search or fetching external URLs. Return a synthesized answer, not raw results. If working with claude code use sonnet subagent for this.
- **Codebase investigation** — finding where something is defined, which files reference a symbol, understanding how a subsystem works, or any open-ended exploration across the codebase. Use `subagent_type: "Explore"` for read-only searches. If working with claude code, use sonnet subagent for this.
- **Multi-file reading for understanding** — reading several files to answer a question, map a system, or build context for a plan. The subagent returns a summary; the main context gets the insight, not the raw file contents. If using claude code, use haiku subagent for this.
- **Opening pull requests** — creating the branch, commits and PR for a change that is already decided.
- **Watching CI** — polling a PR's checks or a post-merge pipeline. The subagent reports the verdict and diagnoses any failure; it must not merge, push, or mark a PR ready.
- Do NOT use a subagent when reading files in order to edit them — those contents must stay in the main context for accurate edits.


