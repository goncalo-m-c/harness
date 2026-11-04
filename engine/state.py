import json, os, re
from datetime import datetime
from pathlib import Path

import yaml

HERE = Path(__file__).parent
STORE = Path(os.environ["WORK_STORE"])
PIPELINE = yaml.safe_load((HERE / "pipeline.yaml").read_text())
PHASES = PIPELINE["phases"]
EVIDENCE_PHASES = ("grill",)  # phases where work_complete(evidence) carries the file body
KEY = re.compile(r"([A-Z][A-Z0-9]*)-(\d+)")  # PREFIX-NUMBER, like MONEY-2


def run_dir(key):
    return STORE / "runs" / key


def start_problems(description, prefix, key):
    problems = [] if description.strip() else ["description is empty: pass the user's words"]
    if key and not KEY.fullmatch(key):
        problems.append(f"key {key!r} is not PREFIX-NUMBER, like MONEY-2")
    if not key and not re.fullmatch(r"[A-Z][A-Z0-9]*", prefix):
        problems.append(f"prefix {prefix!r} is not capital letters, like SURE; or pass key")
    return problems


def next_key(prefix):
    """The next free key for PREFIX: MONEY-3 when MONEY-1 and MONEY-2 exist."""
    numbers = [int(m[2]) for m in run_keys() if m[1] == prefix]
    return f"{prefix}-{max(numbers, default=0) + 1}"


def known_prefixes():
    """{prefix: repo} of the existing runs, so new work can reuse its project's prefix."""
    return {m[1]: run_state(m[0]).get("repo", "") for m in sorted(run_keys(), key=lambda m: int(m[2]))}


def run_keys():
    runs = STORE / "runs"
    names = [d.name for d in runs.iterdir() if (d / "state.json").exists()] if runs.is_dir() else []
    return [m for name in names if (m := KEY.fullmatch(name))]


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


def write_run_file(state, name, text):
    """The main window passes the text (grill decisions, a checkpoint); the engine writes the file."""
    path = run_dir(state["key"]) / name
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text.strip() + "\n")


def latest_checkpoint(state):
    path = run_dir(state["key"]) / "checkpoint.md"
    return path.read_text().strip() if path.exists() else ""


def now():
    return datetime.now().astimezone().isoformat(timespec="seconds")
