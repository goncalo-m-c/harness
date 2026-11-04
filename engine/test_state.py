"""Tests for run keys. Run in Docker: python -m unittest test_state -v"""

import json
import os
import shutil
import tempfile
import unittest

os.environ.setdefault("WORK_STORE", tempfile.mkdtemp())  # one store for all test files

import state  # noqa: E402  (needs WORK_STORE set first)

STORE = state.STORE


class NextKeyTest(unittest.TestCase):
    def setUp(self):
        shutil.rmtree(STORE / "runs", ignore_errors=True)

    def add_run(self, key, repo="/r"):
        path = STORE / "runs" / key / "state.json"
        path.parent.mkdir(parents=True)
        path.write_text(json.dumps({"key": key, "repo": repo}))

    def test_first_key_of_a_prefix_is_1(self):
        self.assertEqual(state.next_key("SURE"), "SURE-1")

    def test_next_key_follows_the_highest_number(self):
        for key in ("MONEY-1", "MONEY-3", "MONEY-10", "SITE-12"):
            self.add_run(key)
        self.assertEqual(state.next_key("MONEY"), "MONEY-11")

    def test_a_folder_without_state_is_not_a_run(self):
        (STORE / "runs" / "MONEY-5").mkdir(parents=True)
        self.assertEqual(state.next_key("MONEY"), "MONEY-1")

    def test_known_prefixes_name_the_repo_of_the_newest_run(self):
        self.add_run("SITE-1", "/old-site")
        self.add_run("SITE-2", "/site")
        self.add_run("MONEY-1", "/money")
        (STORE / "runs" / "openspec").mkdir()
        self.assertEqual(state.known_prefixes(), {"SITE": "/site", "MONEY": "/money"})


if __name__ == "__main__":
    unittest.main()
