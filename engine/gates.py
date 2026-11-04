import json
import os
import re
import subprocess
from pathlib import Path

from state import STORE, phase_spec, run_dir

CI_PASS = {"SUCCESS", "SKIPPED", "NEUTRAL"}
SLUG = re.compile(r"[a-z0-9]+(-[a-z0-9]+)*")
FINDING = re.compile(r"^\s*[-*]\s*(hard|soft)\b", re.I | re.M)  # one finding per line in a review report
HUNK = re.compile(r"^@@ -\S+ \+(\d+)(?:,(\d+))? @@")  # one hunk header of `git diff -U0`
RUFF_CONFIG_HOME = Path(__file__).parent.parent / "settings"  # holds ruff/ruff.toml, the global config


def grill_done(state):
    """Grill ends with the decisions written and the run named: a slug and a git-wt repo."""
    path = run_dir(state["key"]) / "decisions.md"
    reasons = [] if path.exists() and path.read_text().strip() else [f"{path} is missing or blank"]
    if not SLUG.fullmatch(state["slug"]):
        reasons.append("no slug: pass slug to work_complete, lowercase words joined by -, like net-worth-split")
    if not state["repo"] or not (Path(state["repo"]) / ".bare").is_dir():
        reasons.append(f"repo {state['repo']!r} is not a git-wt repo (no .bare): ask the user where the code lives")
    return not reasons, reasons


def openspec_valid(state):
    rc, out = shell(
        ["openspec", "validate", state["change"], "--strict", "--no-interactive"], STORE
    )
    return rc == 0, [] if rc == 0 else [out[-1500:]]


def committed_and_tasks_done(state):
    wt = state["worktree"]
    if not Path(wt).is_dir():
        return False, [f"worktree {wt} does not exist"]
    base = base_ref(wt)
    reasons = []
    _, ahead = shell(["git", "rev-list", "--count", f"{base}..HEAD"], wt)
    if not ahead.isdigit() or int(ahead) < 1:
        reasons.append(f"no commit ahead of {base}")
    if shell(["git", "status", "--porcelain"], wt)[1]:
        reasons.append("worktree has uncommitted changes")
    tasks = STORE / "openspec" / "changes" / state["change"] / "tasks.md"
    if not tasks.exists() or "- [ ]" in tasks.read_text():
        reasons.append(f"{tasks} is missing or has unticked tasks")
    reasons += ruff_problems(wt, base)
    return not reasons, reasons


def review_passed(state):
    """The reviewers write the reports. The engine counts the `hard` findings itself."""
    wt = state["worktree"]
    if not Path(wt).is_dir():
        return False, [f"worktree {wt} does not exist"]
    commit_time = int(shell(["git", "log", "-1", "--format=%ct"], wt)[1] or 0)
    reasons = []
    for agent in phase_spec("review")["agents"]:
        axis = agent.removeprefix("work-reviewer-")
        report = run_dir(state["key"]) / "reviews" / f"{axis}.md"
        reasons += report_problems(agent, report, commit_time)
    reasons += ruff_problems(wt, base_ref(wt))
    return not reasons, reasons


def report_problems(agent, report, commit_time):
    if not report.exists():
        return [f"{agent}: no report at {report}; dispatch it"]
    if int(report.stat().st_mtime) < commit_time:
        return [f"{agent}: report is older than the last commit; dispatch it again"]
    text = report.read_text()
    kinds = [kind.lower() for kind in FINDING.findall(text)]
    if not kinds and not text.strip().lower().startswith("no findings"):
        return [f"{agent}: report has no `- hard:` or `- soft:` lines and is not `No findings.`"]
    hard = kinds.count("hard")
    return [f"{agent}: {hard} hard finding(s) open in {report.name}"] if hard else []


def ruff_problems(wt: str, base: str) -> list[str]:
    """Ruff errors on Python lines the branch added. Old code in a changed file does not count."""
    rc, diff = shell(["git", "diff", "-U0", "--diff-filter=d", f"{base}...HEAD", "--", "*.py", "*.pyi"], wt)
    if rc != 0:
        return [f"git diff failed, so ruff could not check: {diff[-300:]}"]
    added = added_lines(diff)
    if not added:
        return []
    files = sorted({path for path, _ in added})
    env = os.environ | {"XDG_CONFIG_HOME": str(RUFF_CONFIG_HOME)}  # used only when the repo has no ruff config
    p = subprocess.run(["ruff", "check", "--output-format", "json", *files], cwd=wt, capture_output=True, text=True, env=env, check=False)
    if p.returncode not in (0, 1):
        return [f"ruff could not run: {p.stderr.strip()[-300:]}"]
    errors = [(os.path.relpath(e["filename"], wt), e["location"]["row"], e) for e in json.loads(p.stdout)]
    return [f"ruff: {path}:{row} {e['code']} {e['message']}" for path, row, e in errors if (path, row) in added]


def added_lines(diff: str) -> set[tuple[str, int]]:
    """(path, line number) for every line a `git diff -U0` adds."""
    added, path = set(), ""
    for line in diff.splitlines():
        if line.startswith("+++ b/"):
            path = line.removeprefix("+++ b/")
        elif hunk := HUNK.match(line):
            start, count = int(hunk[1]), int(hunk[2] or 1)
            added |= {(path, n) for n in range(start, start + count)}
    return added


def base_ref(wt: str) -> str:
    rc, head = shell(["git", "symbolic-ref", "--short", "refs/remotes/origin/HEAD"], wt)
    return head if rc == 0 else "origin/main"


def branch_pushed(state):
    _, remote = shell(
        ["git", "rev-parse", f"refs/remotes/origin/{state['branch']}"], state["worktree"]
    )
    ok = remote == head_of(state["worktree"])
    return ok, [] if ok else [f"origin/{state['branch']} is not at HEAD; push first"]


def ci_green(state):
    """The branch is pushed. If the repo has CI, every check of the PR head passed."""
    ok, reasons = branch_pushed(state)
    if not ok or not (Path(state["worktree"]) / ".github" / "workflows").is_dir():
        return ok, reasons
    path = run_dir(state["key"]) / "ci" / "latest.json"
    if not path.exists():
        return False, [f"{path} is missing; dispatch work-pr"]
    result = json.loads(path.read_text())
    if result.get("headRefOid") != head_of(state["worktree"]):
        return False, ["CI result is for an older commit; dispatch work-pr again"]
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
    "grill_done": grill_done,
    "openspec_valid": openspec_valid,
    "committed_and_tasks_done": committed_and_tasks_done,
    "review_passed": review_passed,
    "ci_green": ci_green,
}
