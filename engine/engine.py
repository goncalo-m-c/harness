"""Work engine: an MCP server that owns run state and checks phase gates.
The 6 tools below are the public contract. pipeline.yaml is the map."""

from mcp.server.fastmcp import FastMCP

from dispatch import TASK_AGENTS, instructions, log_and_dispatch_task
from gates import GATES
from models import model_problems, models_table
from state import (
    EVIDENCE_PHASES,
    PHASES,
    advance,
    known_prefixes,
    latest_checkpoint,
    name_run,
    next_key,
    phase_spec,
    record,
    run_dir,
    run_state,
    start_problems,
    write_run_file,
)

mcp = FastMCP("work")
ASK_APPROVAL = "Ask the user to approve; only they may trigger work_approve."
TASKS_PER_CHECKPOINT = 5
SAVE_CHECKPOINT = (
    "Save a checkpoint now: call work_checkpoint with what is done, what was decided "
    "and what is still open. Tell the user in one line."
)


@mcp.tool()
def work_start(description: str, prefix: str = "", key: str = "", models: dict | None = None) -> str:
    """Create a run from the user's DESCRIPTION and return the grill instructions.
    The key is KEY when the user gave one, else the next free number for PREFIX (like MONEY-2).
    Grill sets the slug and the repo at its end.
    Without MODELS (agent -> model), create nothing and return the models and prefixes to confirm."""
    if key and run_dir(key).exists():
        return f"Run {key} already exists. Call work_next instead."
    if models is None:
        return models_table() + prefixes_table()
    problems = model_problems(models) + start_problems(description, prefix, key)
    if problems:
        return "Start refused, nothing created:\n- " + "\n- ".join(problems)
    key = key or next_key(prefix)
    state = dict(key=key, slug="", change="", branch="", repo="", worktree="")
    state |= dict(phase=PHASES[0]["name"], status="in_progress", pr_url="", models=models)
    state |= dict(tasks_since_checkpoint=0, history=[])
    record(state, "created")
    write_run_file(state, "ticket.md", f"# {key}\n\n{description}")
    return f"Created run {key}.\n\n" + work_next(key)


@mcp.tool()
def work_next(key: str) -> str:
    """Return the current phase, its instructions, its gate, whether approval is pending,
    and the latest checkpoint."""
    state = run_state(key)
    if state["status"] == "done":
        return f"Run {key} is done. All phases passed."
    text = f"Phase: {state['phase']}\nStatus: {state['status']}\nGate: {phase_spec(state['phase'])['gate']}\n\n"
    checkpoint = latest_checkpoint(state)
    if checkpoint:
        text += f"## Latest checkpoint\n\n{checkpoint}\n\n"
    if state["status"] == "awaiting_approval":
        return f"{text}Approval is pending. {ASK_APPROVAL}"
    return text + instructions(state)


@mcp.tool()
def work_complete(key: str, evidence: str = "", slug: str = "", repo: str = "") -> str:
    """Run the gate of the current phase. On pass, advance or wait for approval.
    In grill, EVIDENCE is the decisions (the engine writes the file), SLUG names the branch
    and REPO is the git-wt repo for the code. In pr, EVIDENCE is the PR URL. Review needs none."""
    state = run_state(key)
    if state["status"] != "in_progress":
        record(state, "complete_refused", f"status is {state['status']}")
        return f"Cannot complete: status is {state['status']}. Call work_next."
    spec = phase_spec(state["phase"])
    if state["phase"] in EVIDENCE_PHASES and evidence.strip():
        write_run_file(state, "decisions.md", evidence)
    if state["phase"] == "grill" and slug and repo:
        name_run(state, slug, repo)
    ok, reasons = GATES[spec["gate"]](state)
    if not ok:
        record(state, "gate_failed", "; ".join(reasons)[:300])
        return "Gate failed:\n- " + "\n- ".join(reasons)
    if state["phase"] == "pr":
        state["pr_url"] = evidence
    if spec.get("needs_approval"):
        state["status"] = "awaiting_approval"
        record(state, "gate_passed")
        return f"Gate passed. {SAVE_CHECKPOINT} Then: {ASK_APPROVAL}"
    advance(state)
    return f"Gate passed. {SAVE_CHECKPOINT}\n\n" + work_next(key)


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
    state["tasks_since_checkpoint"] = state.get("tasks_since_checkpoint", 0) + 1
    record(state, "task", kind)
    text = log_and_dispatch_task(state, kind, request)
    if state["tasks_since_checkpoint"] >= TASKS_PER_CHECKPOINT:
        text += f"\n\nAfter you relay the summary: {SAVE_CHECKPOINT}"
    return text


@mcp.tool()
def work_checkpoint(key: str, summary: str) -> str:
    """Save the run's latest checkpoint: what is done, what was decided, what is still open.
    It replaces the previous one, so it must cover the whole run. work_next shows it to a fresh session."""
    state = run_state(key)
    if not summary.strip():
        return "Refused: the summary is empty."
    write_run_file(state, "checkpoint.md", summary)
    state["tasks_since_checkpoint"] = 0
    record(state, "checkpoint")
    return f"Checkpoint saved. To start fresh, the user runs /clear, then /work {key}."


def prefixes_table():
    rows = "\n".join(f"{p:<10}{repo or '(repo not set yet)'}" for p, repo in known_prefixes().items())
    return (
        "\n\nKey prefixes in use:\n\n" + (rows or "none yet") + "\n\n"
        "Pick the prefix for this work with the user: one above, or a new one (capital letters, like SURE). "
        "Pass it as prefix. If the user already has a key (from Jira, for example), pass key instead."
    )


if __name__ == "__main__":
    mcp.run()
