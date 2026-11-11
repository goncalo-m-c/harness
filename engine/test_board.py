"""Tests for the board module and the events that reach it. Run in Docker: python -m unittest test_board -v"""

import importlib
import json
import os
import tempfile
import unittest
from unittest import mock

os.environ.setdefault("WORK_STORE", tempfile.mkdtemp())  # one store for all test files

import board

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


class BoardTest(unittest.TestCase):
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
