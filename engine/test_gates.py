"""Tests for the grill, review and ruff gates. Run in Docker: python -m unittest test_gates -v"""

import os
import subprocess
import tempfile
import unittest
from pathlib import Path

os.environ.setdefault("WORK_STORE", tempfile.mkdtemp())  # one store for all test files

import gates  # noqa: E402  (needs WORK_STORE set first)

STORE = gates.STORE

GIT_IDENTITY = {"GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@t", "GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@t"}


class ReviewGateTest(unittest.TestCase):
    def setUp(self):
        self.repo = Path(tempfile.mkdtemp())
        self.git("init", "-q")
        (self.repo / "a.txt").write_text("a")
        self.git("add", "-A")
        self.git("commit", "-q", "-m", "Add a")
        self.git("update-ref", "refs/remotes/origin/main", "HEAD")  # the ruff check diffs against origin/main
        self.state = {"key": "T-1", "worktree": str(self.repo)}
        self.reviews = STORE / "runs" / "T-1" / "reviews"
        self.reviews.mkdir(parents=True, exist_ok=True)
        for old in self.reviews.glob("*.md"):
            old.unlink()

    def git(self, *args):
        subprocess.run(["git", "-C", str(self.repo), *args], check=True, env={**os.environ, **GIT_IDENTITY})

    def write_report(self, axis, text, seconds_before_commit=0):
        path = self.reviews / f"{axis}.md"
        path.write_text(text)
        if seconds_before_commit:
            commit_time = int(subprocess.check_output(["git", "-C", str(self.repo), "log", "-1", "--format=%ct"]))
            stamp = commit_time - seconds_before_commit
            os.utime(path, (stamp, stamp))

    def write_both(self, spec="No findings.", standards="No findings."):
        self.write_report("spec", spec)
        self.write_report("standards", standards)

    def test_passes_when_both_reports_are_clean(self):
        self.write_both()
        self.assertEqual(gates.review_passed(self.state), (True, []))

    def test_soft_findings_do_not_block(self):
        self.write_both(standards="- soft: a.py:3 — rename x\n- Soft: a.py:9 — shorter")
        self.assertTrue(gates.review_passed(self.state)[0])

    def test_hard_finding_blocks(self):
        self.write_both(spec="- hard: a.py:1 — requirement 2 is missing\n- soft: a.py:2 — nit")
        ok, reasons = gates.review_passed(self.state)
        self.assertFalse(ok)
        self.assertIn("work-reviewer-spec: 1 hard finding(s)", reasons[0])

    def test_hard_is_found_with_other_markers_and_case(self):
        self.write_both(standards="* HARD: a.py:1 — bad")
        self.assertFalse(gates.review_passed(self.state)[0])

    def test_missing_report_blocks(self):
        self.write_report("spec", "No findings.")
        ok, reasons = gates.review_passed(self.state)
        self.assertFalse(ok)
        self.assertIn("work-reviewer-standards: no report", reasons[0])

    def test_report_older_than_last_commit_blocks(self):
        self.write_report("spec", "No findings.")
        self.write_report("standards", "No findings.", seconds_before_commit=60)
        ok, reasons = gates.review_passed(self.state)
        self.assertFalse(ok)
        self.assertIn("older than the last commit", reasons[0])

    def test_report_without_findings_or_no_findings_line_blocks(self):
        self.write_both(spec="Looks good to me, ship it.")
        ok, reasons = gates.review_passed(self.state)
        self.assertFalse(ok)
        self.assertIn("work-reviewer-spec: report has no", reasons[0])

    def test_a_verdict_line_written_by_hand_is_ignored(self):
        self.write_both(spec="verdict: pass\n- hard: a.py:1 — still open")
        self.assertFalse(gates.review_passed(self.state)[0])

    def test_missing_worktree_blocks(self):
        ok, reasons = gates.review_passed({"key": "T-1", "worktree": "/does/not/exist"})
        self.assertFalse(ok)
        self.assertIn("does not exist", reasons[0])


class RuffGateTest(unittest.TestCase):
    """Ruff errors count only on lines the branch added. Needs ruff, as in the engine image."""

    def setUp(self) -> None:
        self.repo = Path(tempfile.mkdtemp())
        self.git("init", "-q")
        (self.repo / "old.py").write_text("import os\n")  # an old error: unused import
        self.git("add", "-A")
        self.git("commit", "-q", "-m", "Add old")
        self.base = subprocess.check_output(["git", "-C", str(self.repo), "rev-parse", "HEAD"], text=True).strip()

    def git(self, *args: str) -> None:
        subprocess.run(["git", "-C", str(self.repo), *args], check=True, env={**os.environ, **GIT_IDENTITY})

    def commit(self, name: str, text: str) -> None:
        (self.repo / name).write_text(text)
        self.git("add", "-A")
        self.git("commit", "-q", "-m", f"Change {name}")

    def test_error_on_a_new_line_blocks(self) -> None:
        self.commit("new.py", "def LoadThing() -> None:\n    pass\n")
        problems = gates.ruff_problems(str(self.repo), self.base)
        self.assertEqual(len(problems), 1)
        self.assertIn("new.py:1 N802", problems[0])

    def test_old_error_in_a_changed_file_does_not_block(self) -> None:
        self.commit("old.py", "import os\n\nSIZE = 1\n")
        self.assertEqual(gates.ruff_problems(str(self.repo), self.base), [])

    def test_no_python_change_runs_nothing(self) -> None:
        self.commit("notes.md", "hello\n")
        self.assertEqual(gates.ruff_problems(str(self.repo), self.base), [])

    def test_git_failure_blocks_instead_of_passing(self) -> None:
        problems = gates.ruff_problems(str(self.repo), "no-such-ref")
        self.assertIn("git diff failed", problems[0])


class GrillGateTest(unittest.TestCase):
    def setUp(self) -> None:
        self.repo = Path(tempfile.mkdtemp())
        (self.repo / ".bare").mkdir()
        self.state = {"key": "G-1", "slug": "net-worth-split", "repo": str(self.repo)}
        decisions = STORE / "runs" / "G-1" / "decisions.md"
        decisions.parent.mkdir(parents=True, exist_ok=True)
        decisions.write_text("- 2026-11-04: split by owner\n")

    def test_passes_with_decisions_slug_and_git_wt_repo(self) -> None:
        self.assertEqual(gates.grill_done(self.state), (True, []))

    def test_missing_slug_blocks(self) -> None:
        ok, reasons = gates.grill_done({**self.state, "slug": ""})
        self.assertFalse(ok)
        self.assertIn("no slug", reasons[0])

    def test_slug_with_spaces_or_capitals_blocks(self) -> None:
        self.assertFalse(gates.grill_done({**self.state, "slug": "Net worth"})[0])

    def test_repo_without_bare_blocks(self) -> None:
        for repo in ("", tempfile.mkdtemp()):
            ok, reasons = gates.grill_done({**self.state, "repo": repo})
            self.assertFalse(ok)
            self.assertIn("not a git-wt repo", reasons[0])


if __name__ == "__main__":
    unittest.main()
