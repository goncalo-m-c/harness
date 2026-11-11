"""The GitHub project board. The only code that talks to GitHub, through the gh CLI.
WORK_PROJECT is owner/number, like owner/2. Two narrow tokens, one per kind of call:
WORK_BOARD_TOKEN (classic: project, read:org, read:discussion) for the board, and
WORK_ISSUES_TOKEN (fine-grained: Issues read and write) for comments. GitHub cannot give a
narrower token for a personal board. Neither token can push code. Both tokens are removed from
the environment when this module loads. Each gh call gets only the token for its job, as
GH_TOKEN. Any GH_TOKEN of the outside environment is dropped."""

import json
import os
import re
import subprocess
from functools import cache

PROJECT = re.compile(r"([\w.-]+)/(\d+)")
BOARD_TOKEN = "WORK_BOARD_TOKEN"
ISSUES_TOKEN = "WORK_ISSUES_TOKEN"
# Popped at import, so no other child process of the engine (git, ruff, openspec) inherits them.
TOKENS = {name: os.environ.pop(name, "") for name in (BOARD_TOKEN, ISSUES_TOKEN)}


class BoardError(Exception):
    pass


def enabled() -> bool:
    return bool(os.environ.get("WORK_PROJECT"))


def add(issue_url: str) -> str:
    """Put the issue on the board and return the item id. Adding twice is safe."""
    owner, number = project_ref()
    item = gh_json(BOARD_TOKEN, "project", "item-add", number, "--owner", owner, "--url", issue_url, "--format", "json")
    return item["id"]


def move(item_id: str, lane: str) -> None:
    owner, number = project_ref()
    field_id, lanes = status_field(owner, number)
    if lane not in lanes:
        raise BoardError(f"lane {lane!r} is not a Status option of the board: {', '.join(lanes)}")
    gh(
        BOARD_TOKEN, "project", "item-edit", "--project-id", project_id(owner, number), "--id", item_id,
        "--field-id", field_id, "--single-select-option-id", lanes[lane],
    )


def comment(issue_url: str, text: str) -> None:
    gh(ISSUES_TOKEN, "issue", "comment", issue_url, "--body", text)


def project_ref() -> tuple[str, str]:
    value = os.environ.get("WORK_PROJECT", "")
    match = PROJECT.fullmatch(value)
    if not match:
        raise BoardError(f"WORK_PROJECT {value!r} is not owner/number, like owner/2")
    return match[1], match[2]


@cache
def status_field(owner: str, number: str) -> tuple[str, dict[str, str]]:
    """The id of the Status field and {lane name: option id}."""
    fields = gh_json(BOARD_TOKEN, "project", "field-list", number, "--owner", owner, "--format", "json")["fields"]
    status = next((f for f in fields if f["name"] == "Status"), None)
    if status is None:
        raise BoardError(f"project {owner}/{number} has no Status field")
    return status["id"], {o["name"]: o["id"] for o in status["options"]}


@cache
def project_id(owner: str, number: str) -> str:
    return gh_json(BOARD_TOKEN, "project", "view", number, "--owner", owner, "--format", "json")["id"]


def gh_json(token_var: str, *args: str) -> dict:
    return json.loads(gh(token_var, *args))


def gh(token_var: str, *args: str) -> str:
    """Run gh with the token TOKENS[token_var] as GH_TOKEN, and no other token."""
    token = TOKENS.get(token_var, "")
    if not token:
        raise BoardError(f"{token_var} is not set: gh needs it for this call")
    env = {k: v for k, v in os.environ.items() if k not in ("GH_TOKEN", "GITHUB_TOKEN")} | {"GH_TOKEN": token}
    try:
        done = subprocess.run(["gh", *args], check=False, capture_output=True, text=True, env=env)
    except OSError as error:
        raise BoardError(f"cannot run gh: {error}") from error
    if done.returncode != 0:
        raise BoardError(f"gh {' '.join(args[:2])} failed: {done.stderr.strip()[:300]}")
    return done.stdout
