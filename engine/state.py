import json
import os
import re
import subprocess
from collections.abc import Callable
from datetime import datetime
from pathlib import Path

import board
import yaml

HERE = Path(__file__).parent
STORE = Path(os.environ["WORK_STORE"])
PIPELINE = yaml.safe_load((HERE / "pipeline.yaml").read_text())
PHASES = PIPELINE["phases"]
EVIDENCE_PHASES = ("grill",)  # phases where work_complete(evidence) carries the file body
KEY = re.compile(r"([A-Z][A-Z0-9]*)-(\d+)")  # PREFIX-NUMBER, like MONEY-2
ISSUE_URL = re.compile(r"https://github\.com/[\w.-]+/[\w.-]+/issues/\d+")
REMOTE = re.compile(r"(?:https://github\.com/|git@github\.com:|ssh://git@github\.com/)([\w.-]+/[\w.-]+?)(?:\.git)?/?")
ISSUE_SHORT = re.compile(r"([\w.-]+/[\w.-]+)#(\d+)")  # owner/repo#n


def run_dir(key):
    return STORE / "runs" / key


def start_problems(description: str, prefix: str, key: str, issue: str = "") -> list[str]:
    problems = [] if description.strip() else ["description is empty: pass the user's words"]
    if key and not KEY.fullmatch(key):
        problems.append(f"key {key!r} is not PREFIX-NUMBER, like MONEY-2")
    if not key and not re.fullmatch(r"[A-Z][A-Z0-9]*", prefix):
        problems.append(f"prefix {prefix!r} is not capital letters, like SURE; or pass key")
    if issue and not issue_url(issue):
        problems.append(f"issue {issue!r} is not a GitHub issue URL or owner/repo#n")
    return problems


def issue_url(issue: str) -> str:
    """The issue URL for a URL or owner/repo#n; empty when ISSUE is neither."""
    if ISSUE_URL.fullmatch(issue):
        return issue
    short = ISSUE_SHORT.fullmatch(issue)
    return f"https://github.com/{short[1]}/issues/{short[2]}" if short else ""


def next_key(prefix: str) -> str:
    """The next free key for PREFIX: MONEY-3 when MONEY-1 and MONEY-2 exist."""
    numbers = [int(m[2]) for m in run_keys() if m[1] == prefix]
    return f"{prefix}-{max(numbers, default=0) + 1}"


def known_prefixes() -> dict[str, str]:
    """{prefix: repo} of the existing runs, so new work can reuse its project's prefix."""
    return {m[1]: run_state(m[0]).get("repo", "") for m in sorted(run_keys(), key=lambda m: int(m[2]))}


def run_keys() -> list[re.Match[str]]:
    runs = STORE / "runs"
    names = [d.name for d in runs.iterdir() if (d / "state.json").exists()] if runs.is_dir() else []
    return [m for name in names if (m := KEY.fullmatch(name))]


def run_state(key):
    return json.loads((run_dir(key) / "state.json").read_text())


def phase_spec(name):
    return next(p for p in PHASES if p["name"] == name)


def link_issue(state: dict, issue: str) -> None:
    """Save the run's issue. With a board, put the card in the lane of the first phase."""
    if not issue:
        return
    state["issue"] = issue
    if board.enabled() and (item := board_call(state, board.add, issue)):
        state["board_item"] = item
        board_call(state, board.move, item, phase_spec(state["phase"])["lane"])
    save(state)


def board_call(state: dict, action: Callable, *args: str) -> str | None:
    """Run a board call. A GitHub error never stops the run: it becomes a github_failed event."""
    try:
        return action(*args)
    except board.BoardError as error:
        record(state, "github_failed", str(error)[:300])


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
    save(state)


def save(state: dict) -> None:
    base_real = os.path.realpath(STORE / "runs")
    path = run_dir(state["key"]) / "state.json"
    target_real = os.path.realpath(path)
    if os.path.commonpath([base_real, target_real]) != base_real:
        raise Exception("Invalid file path")
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(".tmp")
    tmp.write_text(json.dumps(state, indent=2))
    tmp.replace(path)


def log_task(state, kind, request):
    base_real = os.path.realpath(STORE / "runs")
    path = run_dir(state["key"]) / "tasks.md"
    target_real = os.path.realpath(path)
    if os.path.commonpath([base_real, target_real]) != base_real:
        raise Exception("Invalid file path")
    with open(path, "a") as f:
        f.write(f"- {now()} [{state['phase']}] {kind}: {request}\n")


def name_run(state: dict, slug: str, repo: str) -> None:
    """Grill knows the work at its end, so it names the run. Branch and worktree follow."""
    branch = f"{state['key'].lower()}-{slug}"
    state |= {"slug": slug, "change": slug, "branch": branch, "repo": repo, "worktree": f"{repo}/{branch}"}
    if state.get("issue") and (problem := issue_repo_problem(state["issue"], repo)):
        state |= {"issue": "", "board_item": ""}
        record(state, "github_skipped", f"{problem}: the board is off for this run")


def issue_repo_problem(issue: str, repo: str) -> str:
    """Why the issue may not be used with the code in REPO; empty when both are in the same GitHub repo."""
    in_issue = issue_slug(issue)
    in_code = origin_slug(repo)
    if not in_code:
        return f"cannot read the origin of {repo}"
    if in_issue.lower() != in_code.lower():
        return f"issue is in {in_issue}, the code is in {in_code}"
    return ""


def issue_slug(issue: str) -> str:
    """owner/repo of an issue URL."""
    return "/".join(issue.split("/")[3:5])


def origin_slug(repo: str) -> str:
    """owner/repo of the git origin of REPO; empty when it cannot be read or is not on GitHub."""
    done = subprocess.run(["git", "-C", repo, "remote", "get-url", "origin"], check=False, capture_output=True, text=True)
    match = REMOTE.fullmatch(done.stdout.strip()) if done.returncode == 0 else None
    return match[1] if match else ""


def write_run_file(state, name, text):
    """The main window passes the text (grill decisions, a checkpoint); the engine writes the file."""
    base_real = os.path.realpath(STORE / "runs")
    path = run_dir(state["key"]) / name
    target_real = os.path.realpath(path)
    if os.path.commonpath([base_real, target_real]) != base_real:
        raise Exception("Invalid file path")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text.strip() + "\n")


def latest_checkpoint(state):
    path = run_dir(state["key"]) / "checkpoint.md"
    return path.read_text().strip() if path.exists() else ""


def now():
    return datetime.now().astimezone().isoformat(timespec="seconds")
