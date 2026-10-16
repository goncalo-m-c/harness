from models import phase_models
from state import HERE, STORE, log_task, phase_spec

RULES_DIR = HERE.parent / "rules"
TASK_AGENTS = {"edit": "work-implementer", "investigate": "work-explorer"}
TASK_MAIN_STEPS = "1. Read the subagent report.\n2. Relay a short summary to the user."


def log_and_dispatch_task(state, kind, request):
    log_task(state, kind, request)
    agent_model = {TASK_AGENTS[kind]: state["models"]["work-implementer"]}
    return dispatch_block(agent_model, task_prompt(state, kind, request), TASK_MAIN_STEPS)


def instructions(state):
    spec = phase_spec(state["phase"])
    text = (HERE / spec["instructions"]).read_text()
    for name in ("key", "change", "worktree", "branch"):
        text = text.replace("{" + name + "}", state[name])
    text = text.replace("{store}", str(STORE))
    rules = rules_block(spec.get("rules", []))
    agents = phase_models(spec)
    if not agents:
        return text + rules
    head, rest = text.split("**Subagent does:**\n")
    prompt, rest = rest.split("**Main does:**\n")
    steps, tail = rest.split("**Write:**")
    agent_model = {a: state["models"][a] for a in agents}
    return dispatch_block(agent_model, prompt + rules, steps) + f"\n\n{head}**Write:**{tail}"


def rules_block(names):
    """The text of rules/<name>.md for each name. Subagents do not see the main chat, so the rules travel in their prompt."""
    if not names:
        return ""
    rules = "\n\n".join(f"### {n}\n{(RULES_DIR / f'{n}.md').read_text().strip()}" for n in names)
    return f"\n\n## Rules to follow\n\n{rules}\n"


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
        rules = rules_block(phase_spec("implement").get("rules", []))
        return where + "Commit with conventional commits. Do not push. Report back." + rules
    return where + "Return a short summary, not raw output."
