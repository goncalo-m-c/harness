"""Tests for the board module and the events that reach it. Run in Docker: python -m unittest test_board -v"""

import importlib
import json
import os
import subprocess
import tempfile
import unittest
from unittest import mock

os.environ.setdefault("WORK_STORE", tempfile.mkdtemp())  # one store for all test files

import board
import models
import state

import engine

TOKENS = {"WORK_BOARD_TOKEN": "board-secret", "WORK_ISSUES_TOKEN": "issues-secret"}

FIELDS = {"fields": [
    {"id": "F0", "name": "Title"},
    {"id": "F1", "name": "Status", "options": [
        {"id": "O1", "name": "Backlog"}, {"id": "O2", "name": "In Progress"}, {"id": "O3", "name": "In Review"},
    ]},
]}


class FakeGh:
    """Stands in for the gh CLI. Records every call and answers by the first two words."""

    def __init__(self, fail: bool = False) -> None:
        self.calls: list[tuple[str, ...]] = []
        self.tokens: list[str] = []  # the token var of each call
        self.fail = fail

    def __call__(self, token_var: str, *args: str) -> str:
        self.tokens.append(token_var)
        self.calls.append(args)
        if self.fail:
            raise board.BoardError("bad credentials")
        answers = {
            ("project", "item-add"): {"id": "ITEM1"},
            ("project", "view"): {"id": "PROJ1"},
            ("project", "field-list"): FIELDS,
        }
        return json.dumps(answers.get(args[:2], {}))


class FakeGhCase(unittest.TestCase):
    """Every test runs with WORK_PROJECT and both tokens set, and gh replaced by FakeGh."""

    def setUp(self) -> None:
        board.project_id.cache_clear()
        board.status_field.cache_clear()
        env = mock.patch.dict(os.environ, {"WORK_PROJECT": "owner/2"})
        env.start()
        self.addCleanup(env.stop)
        self.gh = FakeGh()
        patch = mock.patch.object(board, "gh", self.gh)
        patch.start()
        self.addCleanup(patch.stop)

    def lanes_moved_to(self) -> list[str]:
        options = {"O1": "Backlog", "O2": "In Progress", "O3": "In Review"}
        edits = [c for c in self.gh.calls if c[:2] == ("project", "item-edit")]
        return [options[c[c.index("--single-select-option-id") + 1]] for c in edits]


class BoardTest(FakeGhCase):

    def test_add_returns_the_item_id(self) -> None:
        item = board.add("https://github.com/o/r/issues/3")
        self.assertEqual(item, "ITEM1")
        self.assertEqual(self.gh.calls[0][:5], ("project", "item-add", "2", "--owner", "owner"))

    def test_move_sends_the_option_id_of_the_lane(self) -> None:
        board.move("ITEM1", "In Progress")
        args = self.gh.calls[-1]
        self.assertEqual(args[:2], ("project", "item-edit"))
        for flag, value in (("--project-id", "PROJ1"), ("--id", "ITEM1"), ("--field-id", "F1"),
                            ("--single-select-option-id", "O2")):
            self.assertEqual(args[args.index(flag) + 1], value)

    def test_ids_are_looked_up_once(self) -> None:
        board.move("ITEM1", "Backlog")
        board.move("ITEM1", "In Review")
        lookups = [c for c in self.gh.calls if c[1] in ("view", "field-list")]
        self.assertEqual(len(lookups), 2)

    def test_unknown_lane_is_a_clear_error(self) -> None:
        with self.assertRaisesRegex(board.BoardError, "lane 'Nope' is not a Status option"):
            board.move("ITEM1", "Nope")

    def test_comment_posts_on_the_issue(self) -> None:
        board.comment("https://github.com/o/r/issues/3", "hello")
        self.assertEqual(self.gh.calls[0], ("issue", "comment", "https://github.com/o/r/issues/3", "--body", "hello"))

    def test_project_calls_use_the_board_token_and_comments_the_issues_token(self) -> None:
        board.add("https://github.com/o/r/issues/3")
        board.move("ITEM1", "Backlog")
        board.comment("https://github.com/o/r/issues/3", "hello")
        self.assertEqual(set(self.gh.tokens[:-1]), {"WORK_BOARD_TOKEN"})
        self.assertEqual(self.gh.tokens[-1], "WORK_ISSUES_TOKEN")

    def test_bad_work_project_is_refused(self) -> None:
        with (
            mock.patch.dict(os.environ, {"WORK_PROJECT": "owner"}),
            self.assertRaisesRegex(board.BoardError, "not owner/number"),
        ):
            board.add("https://github.com/o/r/issues/3")

    def test_enabled_follows_work_project(self) -> None:
        self.assertTrue(board.enabled())
        with mock.patch.dict(os.environ, {"WORK_PROJECT": ""}):
            self.assertFalse(board.enabled())


class StartTest(FakeGhCase):
    ISSUE = "https://github.com/o/r/issues/3"

    def all_models(self) -> dict:
        return {a: m for p in state.PHASES for a, m in models.phase_models(p).items()}

    def start_run(self, key: str, issue: str = "") -> dict:
        engine.work_start("a task", key=key, models=self.all_models(), issue=issue)
        return state.run_state(key)

    def test_issue_forms_become_a_url(self) -> None:
        self.assertEqual(state.issue_url(self.ISSUE), self.ISSUE)
        self.assertEqual(state.issue_url("o/r#3"), self.ISSUE)
        self.assertEqual(state.issue_url("nonsense"), "")

    def test_a_bad_issue_is_refused_and_creates_nothing(self) -> None:
        text = engine.work_start("a task", key="T-1", models=self.all_models(), issue="nonsense")
        self.assertIn("Start refused", text)
        self.assertFalse(state.run_dir("T-1").exists())

    def test_start_with_an_issue_adds_the_card_and_puts_it_in_backlog(self) -> None:
        run = self.start_run("T-2", "o/r#3")
        self.assertEqual((run["issue"], run["board_item"]), (self.ISSUE, "ITEM1"))
        self.assertEqual(self.gh.calls[0][:2], ("project", "item-add"))
        self.assertEqual(self.lanes_moved_to()[-1], "Backlog")

    def test_start_without_an_issue_tracks_nothing(self) -> None:
        run = self.start_run("T-3")
        self.assertEqual((run["issue"], run["board_item"]), ("", ""))
        self.assertEqual(self.gh.calls, [])

    def test_start_without_work_project_makes_no_gh_call(self) -> None:
        with mock.patch.dict(os.environ, {"WORK_PROJECT": ""}):
            run = self.start_run("T-4", self.ISSUE)
        self.assertEqual((run["issue"], run["board_item"]), (self.ISSUE, ""))
        self.assertEqual(self.gh.calls, [])

    def test_a_failing_gh_still_creates_the_run(self) -> None:
        self.gh.fail = True
        run = self.start_run("T-5", self.ISSUE)
        self.assertEqual(run["board_item"], "")
        self.assertEqual([h["event"] for h in run["history"]], ["created", "github_failed"])


class SameRepoTest(FakeGhCase):
    """At the end of grill the issue must be in the repo of the code, or the board is off for the run."""
    ISSUE = "https://github.com/o/r/issues/3"

    def named_run(self, origin: str, issue: str = ISSUE) -> dict:
        repo = tempfile.mkdtemp()
        subprocess.run(["git", "-C", repo, "init", "-q"], check=True)
        if origin:
            subprocess.run(["git", "-C", repo, "remote", "add", "origin", origin], check=True)
        run = {"key": "T-6", "phase": "grill", "status": "in_progress", "history": [],
               "issue": issue, "board_item": "ITEM1"}
        state.name_run(run, "slug", repo)
        return run

    def test_the_same_repo_keeps_the_issue_for_every_origin_form(self) -> None:
        for origin in ("https://github.com/o/r", "https://github.com/o/r.git", "git@github.com:o/r.git",
                       "ssh://git@github.com/o/r.git", "https://github.com/O/R.git"):
            with self.subTest(origin=origin):
                run = self.named_run(origin)
                self.assertEqual((run["issue"], run["board_item"], run["history"]), (self.ISSUE, "ITEM1", []))

    def test_another_repo_clears_the_issue_and_records_why(self) -> None:
        run = self.named_run("git@github.com:o/x.git")
        self.assertEqual((run["issue"], run["board_item"]), ("", ""))
        self.assertEqual([h["event"] for h in run["history"]], ["github_skipped"])
        self.assertIn("issue is in o/r, the code is in o/x: the board is off", run["history"][0]["detail"])
        self.assertEqual(self.gh.calls, [])
        state.record(run, "gate_failed", "x")
        self.assertEqual(self.gh.calls, [])

    def test_an_unreadable_origin_clears_the_issue(self) -> None:
        for origin in ("", "https://example.com/o/r.git"):
            with self.subTest(origin=origin):
                run = self.named_run(origin)
                self.assertEqual(run["issue"], "")
                self.assertEqual(run["history"][0]["event"], "github_skipped")

    def test_a_run_without_an_issue_records_nothing(self) -> None:
        run = self.named_run("git@github.com:o/x.git", issue="")
        self.assertEqual(run["history"], [])


class AdvanceTest(FakeGhCase):
    def setUp(self) -> None:
        super().setUp()
        self.run = {"key": "T-9", "phase": "spec", "status": "in_progress", "history": [],
                    "issue": "https://github.com/o/r/issues/3", "board_item": "ITEM1"}

    def advance_through(self, *phases: str) -> None:
        for phase in phases:
            self.run["phase"] = phase
            state.advance(self.run)

    def test_a_lane_change_moves_the_card(self) -> None:
        self.advance_through("spec")  # Backlog to In Progress (implement)
        self.assertEqual(self.lanes_moved_to(), ["In Progress"])

    def test_the_same_lane_does_not_move_the_card(self) -> None:
        self.advance_through("grill", "implement", "review")
        self.assertEqual(self.lanes_moved_to(), [])

    def test_done_moves_the_card_to_in_review(self) -> None:
        self.advance_through("pr")
        self.assertEqual((self.run["status"], self.lanes_moved_to()), ("done", ["In Review"]))

    def test_a_failing_gh_does_not_stop_the_run(self) -> None:
        self.gh.fail = True
        self.advance_through("spec")
        self.assertEqual((self.run["phase"], self.run["status"]), ("implement", "in_progress"))
        events = [h["event"] for h in self.run["history"]]
        self.assertEqual(events, ["entered", "github_failed"])
        self.assertIn("bad credentials", self.run["history"][-1]["detail"])

    def test_without_work_project_there_is_no_gh_call(self) -> None:
        with mock.patch.dict(os.environ, {"WORK_PROJECT": ""}):
            self.advance_through("spec", "pr")
        self.assertEqual(self.gh.calls, [])


class GhHelperTest(unittest.TestCase):
    def run_gh(self, token_var: str, outside: dict) -> dict:
        """Run board.gh with a fake subprocess and return the env that gh received."""
        done = mock.Mock(returncode=0, stdout="{}", stderr="")
        with (
            mock.patch.dict(board.TOKENS, TOKENS),
            mock.patch.dict(os.environ, outside),
            mock.patch.object(board.subprocess, "run", return_value=done) as run,
        ):
            board.gh(token_var, "issue", "comment")
        return run.call_args.kwargs["env"]

    def test_gh_gets_only_the_token_for_its_job(self) -> None:
        env = self.run_gh("WORK_ISSUES_TOKEN", {})
        self.assertEqual(env["GH_TOKEN"], "issues-secret")
        env = self.run_gh("WORK_BOARD_TOKEN", {})
        self.assertEqual(env["GH_TOKEN"], "board-secret")

    def test_an_outside_token_never_reaches_gh(self) -> None:
        env = self.run_gh("WORK_BOARD_TOKEN", {"GH_TOKEN": "login-token", "GITHUB_TOKEN": "other"})
        self.assertEqual(env["GH_TOKEN"], "board-secret")
        self.assertNotIn("GITHUB_TOKEN", env)

    def test_the_other_token_never_reaches_gh(self) -> None:
        env = self.run_gh("WORK_BOARD_TOKEN", {})
        self.assertNotIn("issues-secret", env.values())
        self.assertNotIn("WORK_ISSUES_TOKEN", env)
        self.assertNotIn("WORK_BOARD_TOKEN", env)

    def test_the_tokens_leave_the_environment_at_import(self) -> None:
        with mock.patch.dict(os.environ, TOKENS):
            importlib.reload(board)
            self.assertEqual(board.TOKENS, TOKENS)
            for name in TOKENS:
                self.assertNotIn(name, os.environ)
        importlib.reload(board)  # back to the tokens of the real environment

    def test_a_missing_token_names_the_variable(self) -> None:
        with (
            mock.patch.dict(board.TOKENS, {"WORK_ISSUES_TOKEN": ""}),
            mock.patch.object(board.subprocess, "run") as run,
            self.assertRaisesRegex(board.BoardError, "WORK_ISSUES_TOKEN is not set"),
        ):
            board.gh("WORK_ISSUES_TOKEN", "issue", "comment")
        run.assert_not_called()

    def test_non_zero_exit_raises_board_error(self) -> None:
        done = mock.Mock(returncode=1, stdout="", stderr="HTTP 401")
        with (
            mock.patch.dict(board.TOKENS, TOKENS),
            mock.patch.object(board.subprocess, "run", return_value=done),
            self.assertRaisesRegex(board.BoardError, "HTTP 401"),
        ):
            board.gh("WORK_BOARD_TOKEN", "issue", "comment")


if __name__ == "__main__":
    unittest.main()
