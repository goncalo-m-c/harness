import json, re, subprocess
from pathlib import Path

import yaml

from state import STORE, run_dir

CI_PASS = {"SUCCESS", "SKIPPED", "NEUTRAL"}


def decisions_written(state):
    path = run_dir(state["key"]) / "decisions.md"
    ok = path.exists() and path.read_text().strip() != ""
    return ok, [] if ok else [f"{path} is missing or blank"]


def openspec_valid(state):
    rc, out = shell(
        ["openspec", "validate", state["change"], "--strict", "--no-interactive"], STORE
    )
    return rc == 0, [] if rc == 0 else [out[-1500:]]


def committed_and_tasks_done(state):
    wt = state["worktree"]
    if not Path(wt).is_dir():
        return False, [f"worktree {wt} does not exist"]
    rc, head = shell(["git", "symbolic-ref", "--short", "refs/remotes/origin/HEAD"], wt)
    base = head if rc == 0 else "origin/main"
    reasons = []
    _, ahead = shell(["git", "rev-list", "--count", f"{base}..HEAD"], wt)
    if not ahead.isdigit() or int(ahead) < 1:
        reasons.append(f"no commit ahead of {base}")
    if shell(["git", "status", "--porcelain"], wt)[1]:
        reasons.append("worktree has uncommitted changes")
    tasks = STORE / "openspec" / "changes" / state["change"] / "tasks.md"
    if not tasks.exists() or "- [ ]" in tasks.read_text():
        reasons.append(f"{tasks} is missing or has unticked tasks")
    return not reasons, reasons


def review_passed(state):
    files = [p for p in (run_dir(state["key"]) / "reviews").glob("*.md") if p.stem.isdigit()]
    if not files:
        return False, ["no review file in reviews/"]
    latest = max(files, key=lambda p: int(p.stem))
    front = re.match(r"---\n(.*?)\n---", latest.read_text(), re.S)
    verdict = (yaml.safe_load(front.group(1)) or {}).get("verdict") if front else None
    ok = verdict == "pass"
    return ok, [] if ok else [f"{latest.name} verdict is {verdict}, not pass"]


def branch_pushed(state):
    _, remote = shell(
        ["git", "rev-parse", f"refs/remotes/origin/{state['branch']}"], state["worktree"]
    )
    ok = remote == head_of(state["worktree"])
    return ok, [] if ok else [f"origin/{state['branch']} is not at HEAD; push first"]


def ci_green(state):
    path = run_dir(state["key"]) / "ci" / "latest.json"
    if not path.exists():
        return False, [f"{path} is missing; run the watcher"]
    result = json.loads(path.read_text())
    if result.get("headRefOid") != head_of(state["worktree"]):
        return False, ["CI result is for an older commit; re-run the watcher"]
    checks = result.get("statusCheckRollup") or []
    bad = [
        f"{c.get('name') or c.get('context')}: {outcome(c)}"
        for c in checks
        if outcome(c) not in CI_PASS
    ]
    return bool(checks) and not bad, bad or ([] if checks else ["no checks reported"])


def outcome(check):
    """CheckRun has `conclusion`; StatusContext has `state`."""
    return check.get("conclusion") or check.get("state") or "PENDING"


def head_of(worktree):
    return shell(["git", "rev-parse", "HEAD"], worktree)[1]


def shell(cmd, cwd):
    p = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True)
    return p.returncode, (p.stdout + p.stderr).strip()


GATES = {
    "decisions_written": decisions_written,
    "openspec_valid": openspec_valid,
    "committed_and_tasks_done": committed_and_tasks_done,
    "review_passed": review_passed,
    "branch_pushed": branch_pushed,
    "ci_green": ci_green,
}
