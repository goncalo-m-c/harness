from models import phase_models
from state import HERE, STORE, log_task, phase_spec

TASK_AGENTS = {"edit": "work-implementer", "investigate": "work-explorer"}
TASK_MAIN_STEPS = "1. Read the subagent report.\n2. Relay a short summary to the user."


def log_and_dispatch_task(state, kind, request):
    log_task(state, kind, request)
    agent_model = {TASK_AGENTS[kind]: state["models"]["work-implementer"]}
    return dispatch_block(agent_model, task_prompt(state, kind, request), TASK_MAIN_STEPS)


def instructions(state):
    text = (HERE / phase_spec(state["phase"])["instructions"]).read_text()
    for name in ("key", "change", "worktree", "branch"):
        text = text.replace("{" + name + "}", state[name])
    text = text.replace("{store}", str(STORE))
    agents = phase_models(phase_spec(state["phase"]))
    if not agents:
        return text
    head, rest = text.split("**Subagent does:**\n")
    prompt, rest = rest.split("**Main does:**\n")
    steps, tail = rest.split("**Write:**")
    agent_model = {a: state["models"][a] for a in agents}
    return dispatch_block(agent_model, prompt, steps) + f"\n\n{head}**Write:**{tail}"


def dispatch_block(agent_model, prompt, main_steps):
    names = " and ".join(f"`{a}` with model `{m}`" for a, m in agent_model.items())
    return (
        f"Dispatch subagent{'s' if len(agent_model) > 1 else ''} {names}, with the prompt below. "
        "Pass each model as the Agent tool's `model` parameter. "
        "Do not do this work in the main window.\n\n"
        f"### Subagent prompt\n{prompt.strip()}\n\n### Main window steps\n{main_steps.strip()}"
    )


def task_prompt(state, kind, request):
    where = f"Worktree: {state['worktree']}\nBranch: {state['branch']}\nRequest: {request}\n"
    if kind == "edit":
        return where + "Commit with conventional commits. Do not push. Report back."
    return where + "Return a short summary, not raw output."
