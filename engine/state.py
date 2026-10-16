import json, os
from datetime import datetime
from pathlib import Path

import yaml

HERE = Path(__file__).parent
STORE = Path(os.environ["WORK_STORE"])
PIPELINE = yaml.safe_load((HERE / "pipeline.yaml").read_text())
PHASES = PIPELINE["phases"]
EVIDENCE_PHASES = ("grill",)  # phases where work_complete(evidence) carries the file body


def run_dir(key):
    return STORE / "runs" / key


def run_state(key):
    return json.loads((run_dir(key) / "state.json").read_text())


def phase_spec(name):
    return next(p for p in PHASES if p["name"] == name)


def advance(state):
    names = [p["name"] for p in PHASES]
    i = names.index(state["phase"]) + 1
    if i == len(names):
        state["status"] = "done"
        record(state, "done")
        return
    state["phase"], state["status"] = names[i], "in_progress"
    record(state, "entered")


def record(state, event, detail=""):
    """Append to history and save atomically."""
    entry = {"ts": now(), "phase": state["phase"], "event": event}
    if detail:
        entry["detail"] = detail
    state["history"].append(entry)
    path = run_dir(state["key"]) / "state.json"
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(".tmp")
    tmp.write_text(json.dumps(state, indent=2))
    os.replace(tmp, path)


def log_task(state, kind, request):
    with open(run_dir(state["key"]) / "tasks.md", "a") as f:
        f.write(f"- {now()} [{state['phase']}] {kind}: {request}\n")


def write_evidence(state, text):
    """The main window passes the grill decisions; the engine writes the file."""
    path = run_dir(state["key"]) / "decisions.md"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text.strip() + "\n")


def now():
    return datetime.now().astimezone().isoformat(timespec="seconds")
