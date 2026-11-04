# Glossary

**Approval.** Your yes at the end of the spec phase and the review phase. Only you can give it.

**Chat agent.** The agent you talk to in Claude Code. It talks with you and is told to hand the heavy work to subagents. Also called the main window.

**Change.** One OpenSpec change: the proposal, design, specs and tasks for one ticket. It lives in `openspec/changes/<slug>/` in the store.

**Checkpoint.** A short note of what is done, decided and still open. A fresh chat continues from it. See [Daily use](4-daily-use.md).

**Dispatch.** The chat agent starts a subagent with a prompt and a model. The engine writes the prompt.

**Engine.** The MCP server that owns the state of each run and runs the gates. See [Engine](6-engine.md).

**Gate.** A check in code at the end of each phase. The run moves on only when it passes.

**git-wt layout.** A repo layout where `main` sits in `<repo>/main` and each branch has its own folder next to it.

**Grill.** The first phase. The agent asks you questions until you agree on what to build.

**Hard finding.** A review finding that must be fixed. A `soft` finding is a suggestion and does not block the gate.

**Key.** The ticket ID, like `ABC-123`. It names the run.

**MCP.** Model Context Protocol: the standard way an agent calls the tools of a program like the engine.

**Phase.** One step of a run: grill, spec, implement, review or pr.

**Rule file.** A short list of rules for agents. Some are pasted into prompts, and some load by file type. See [Rules](5-rules.md).

**Run.** One ticket going through all the phases. Its files are in `runs/<KEY>/` in the store.

**Slug.** A short name for the work, like `add-login`. The branch name is the key in lower case plus the slug: `abc-123-add-login`.

**Store.** The folder that holds all runs and specs.

**Subagent.** An agent that the chat agent starts for one job. It starts with a clean context and returns a short report.

**Tier.** The strength of a subagent's model: fast, standard or strong. Each tool turns a tier into a model name.

**Worktree.** A separate folder for one branch of a repo, next to its `main` folder. The implementer is told to work only there.
