# Phases

A run goes through five phases, always in this order.
The order, the agents and the gates are all in [`engine/pipeline.yaml`](../engine/pipeline.yaml).
What the agent does in each phase is in [`engine/phases/`](../engine/phases/).

## The five phases

| Phase | Who works | What it produces | Gate (the check) | You approve? |
|---|---|---|---|---|
| grill | the chat agent, with you | `decisions.md` | the file exists and is not empty | you confirm the decisions |
| spec | `work-spec-writer` | an OpenSpec change: proposal, design, specs, tasks | `openspec validate --strict` passes | **yes** |
| implement | `work-implementer` | commits in the branch folder | one commit or more, clean tree, every task ticked, no new ruff errors | you say go after the hunk review |
| review | `work-reviewer-spec` and `work-reviewer-standards` | two review reports | both reports are newer than the last commit, no `hard` finding, no new ruff errors | **yes**: this allows the push |
| pr | `work-pr` | a draft PR, and the CI result | the branch is pushed; if the repo has CI, every check passed | no |

## What each phase is for

**Grill** makes sure you and the agent agree before any code exists.
Unclear points become decisions now, not surprises later.

**Spec** writes the decisions down in a fixed format, [OpenSpec](https://github.com/Fission-AI/OpenSpec).
The task list in the spec is what the implementer works through.

**Implement** writes the code, in a separate branch folder.
The `main` folder of your repo is never touched.

**Review** looks at the code twice, from two sides:
- The **spec** reviewer asks: does the code do what the spec says, and nothing more?
- The **standards** reviewer asks: does the code follow the repo's rules and the [language rules](5-rules.md)?

**PR** pushes the branch, opens a draft PR and watches CI.
If the repo has no CI, the phase ends when the branch is pushed.

## Gates

A gate is a small Python function in [`engine/gates.py`](../engine/gates.py).
The agent cannot pass a gate by saying so. The engine looks at the real files: the git state, the reports, the CI result.
When a gate fails, the engine sends back the reasons. The agent fixes them and tries again.

## Approvals

Two phases end with your approval: spec and review.
Only you can approve. Claude Code asks you each time the agent calls `work_approve`.
The review approval is also your permission to push.

## Agents and models

Each subagent has a default **tier**: fast, standard or strong.
The tier becomes a model name. For Claude Code: fast is haiku, standard is sonnet, strong is opus.

| Agent | Default tier |
|---|---|
| `work-spec-writer` | standard |
| `work-implementer` | standard |
| `work-reviewer-spec` | strong |
| `work-reviewer-standards` | strong |
| `work-pr` | fast |

You confirm the models when a run starts. The engine saves them for the whole run.
A reviewer may not use the same model as the implementer. A second model catches different mistakes.

Two more agents help with extra requests: `work-explorer` looks things up, and `work-implementer` makes changes.
See [Daily use](4-daily-use.md).

Next: [Daily use](4-daily-use.md).
