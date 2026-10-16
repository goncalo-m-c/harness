import os

from state import PHASES, PIPELINE, phase_spec

CLIENT = os.environ.get("WORK_CLIENT", "claude")
TIER_MODELS = PIPELINE["client_models"][CLIENT]
ALLOWED_NAMES = list(TIER_MODELS.values())


def models_table():
    rows = [
        f"{p['name']:<10}{agent:<26}{model}"
        for p in PHASES
        for agent, model in phase_models(p).items()
    ]
    return (
        "Default models:\n\n" + "\n".join(rows) + "\n\n"
        "Show this table to the user. Ask them to confirm or change any model "
        f"(allowed: {', '.join(ALLOWED_NAMES)}). "
        "Then call work_start again with models={agent: model} for every agent."
    )


def model_problems(models):
    defaults = {a: m for p in PHASES for a, m in phase_models(p).items()}
    problems = [f"missing agent {a}" for a in defaults if a not in models]
    problems += [f"unknown agent {a}" for a in models if a not in defaults]
    problems += [f"{a}: {m} is not allowed" for a, m in models.items() if m not in ALLOWED_NAMES]
    if not problems:
        implementer = models[phase_spec("implement")["agent"]]
        problems += [
            f"{a}: {models[a]} is the same model as the implementer"
            for a in phase_spec("review")["agents"]
            if models[a] == implementer
        ]
    return problems


def phase_models(phase):
    """Default {agent: model} of a phase; empty when the main window does the work."""
    if "agents" in phase:
        tiers = phase["agents"]
    else:
        tiers = {} if phase["agent"] == "main" else {phase["agent"]: phase["tier"]}
    return {agent: TIER_MODELS[tier] for agent, tier in tiers.items()}
