"""Work engine: an MCP server that owns run state and checks phase gates.
The 5 tools below are the public contract. pipeline.yaml is the map."""

from mcp.server.fastmcp import FastMCP

from dispatch import TASK_AGENTS, instructions, log_and_dispatch_task
from gates import GATES
from models import model_problems, models_table
from state import (
    EVIDENCE_PHASES,
    PHASES,
    advance,
    phase_spec,
    record,
    run_dir,
    run_state,
    write_evidence,
)

mcp = FastMCP("work")
ASK_APPROVAL = "Ask the user to approve; only they may trigger work_approve."


@mcp.tool()
def work_start(key: str, slug: str, repo: str, models: dict | None = None) -> str:
    """Create a run for ticket KEY in REPO (git-wt layout) and return the grill instructions.
    Without MODELS (agent -> model), create nothing and return the default table to confirm."""
    if run_dir(key).exists():
        return f"Run {key} already exists. Call work_next instead."
    if models is None:
        return models_table()
    problems = model_problems(models)
    if problems:
        return "Models refused, nothing created:\n- " + "\n- ".join(problems)
    branch = f"{key.lower()}-{slug}"
    state = dict(key=key, slug=slug, change=slug, branch=branch, repo=repo)
    state |= dict(worktree=f"{repo}/{branch}", phase=PHASES[0]["name"], status="in_progress")
    state |= dict(pr_url="", models=models, history=[])
    record(state, "created")
    return work_next(key)


@mcp.tool()
def work_next(key: str) -> str:
    """Return the current phase, its instructions, its gate and whether approval is pending."""
    state = run_state(key)
    if state["status"] == "done":
        return f"Run {key} is done. All phases passed."
    text = f"Phase: {state['phase']}\nStatus: {state['status']}\nGate: {phase_spec(state['phase'])['gate']}\n\n"
    if state["status"] == "awaiting_approval":
        return f"{text}Approval is pending. {ASK_APPROVAL}"
    return text + instructions(state)


@mcp.tool()
def work_complete(key: str, evidence: str = "") -> str:
    """Run the gate of the current phase. On pass, advance or wait for approval.
    EVIDENCE is the grill decisions or the merged review (the engine writes the file), or the PR URL."""
    state = run_state(key)
    if state["status"] != "in_progress":
        record(state, "complete_refused", f"status is {state['status']}")
        return f"Cannot complete: status is {state['status']}. Call work_next."
    spec = phase_spec(state["phase"])
    if state["phase"] in EVIDENCE_PHASES and evidence.strip():
        write_evidence(state, evidence)
    ok, reasons = GATES[spec["gate"]](state)
    if not ok:
        record(state, "gate_failed", "; ".join(reasons)[:300])
        return "Gate failed:\n- " + "\n- ".join(reasons)
    if state["phase"] == "pr":
        state["pr_url"] = evidence
    if spec.get("needs_approval"):
        state["status"] = "awaiting_approval"
        record(state, "gate_passed")
        return f"Gate passed. {ASK_APPROVAL}"
    advance(state)
    return "Gate passed.\n\n" + work_next(key)


@mcp.tool()
def work_approve(key: str) -> str:
    """Human approval for the current phase. Valid only when approval is pending."""
    state = run_state(key)
    if state["status"] != "awaiting_approval":
        record(state, "approve_refused", f"status is {state['status']}")
        return f"Refused: status is {state['status']}, nothing to approve."
    record(state, "approved")
    advance(state)
    return "Approved.\n\n" + work_next(key)


@mcp.tool()
def work_task(key: str, request: str, kind: str) -> str:
    """Log an ad-hoc request and return the subagent dispatch block. Phase and status stay put."""
    state = run_state(key)
    if kind not in TASK_AGENTS:
        return f"Unknown kind {kind!r}. Use one of: {', '.join(TASK_AGENTS)}."
    return log_and_dispatch_task(state, kind, request)


if __name__ == "__main__":
    mcp.run()
