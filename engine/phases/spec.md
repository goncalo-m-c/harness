# Spec
**Goal:** Turn the decisions into a valid OpenSpec change.
**Use:** `openspec instructions <artifact> --change {change} --json`. Follow its output as-is.
**Agent:** `work-spec-writer`
**Subagent does:**
You are `work-spec-writer`. Store: `{store}`. Change: `{change}`.
`openspec` is not on the host. Run each `openspec` command as `docker run --rm -v {store}:{store} -w {store} work-engine:0.1.0 openspec <args>`.
1. Read `{store}/runs/{key}/decisions.md`.
2. In `{store}`, run `openspec new change {change}`.
3. For proposal, specs, design, tasks: run `openspec instructions <artifact> --change {change} --json`. Fill each from the decisions.
4. Run `openspec validate {change} --strict` until it is clean.
5. Never touch code repos. Report the files written and the validate result.
**Main does:**
1. Open the spec for the user: `bash {harness}/scripts/open-spec-pane.sh {store}/openspec/changes/{change}`. It opens a Herdr app pane beside yours that shows the spec as markdown.
2. Tell the user what the spec says, in a few lines. Ask for approval.
3. Call `work_complete`, then wait. Only the user triggers `work_approve`.
**Write:** `{store}/openspec/changes/{change}/` (proposal.md, design.md, tasks.md, specs/)
**Gate:** `openspec_valid`. `openspec validate {change} --strict` passes. The user must approve.
**Never:**
- Never use the `to-spec` skill.
- Never call `work_approve` yourself. Only the user approves.
