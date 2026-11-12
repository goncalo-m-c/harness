---
name: factory
description: Take one card of the Trello board "Factory" from ToDo to a draft PR, with the build and review boxes. Use when the user runs /factory <card number>.
disable-model-invocation: true
---

# Factory

The user gives a card number `<n>`. The scripts are the gates. You move a card only after its gate passed, and you report what a script said, nothing more.

- Scripts: `~/Projects/harness/main/factory/box/` (below: `box/`).
- Run folder: `~/.factory/runs/factory-<n>/`.
- Find the card on the board "Factory" with `trelloReadCard` (`list_by_board`). Its URL holds `/<n>-`. Use its ARI for every write.

## What to do, by the card's list

**ToDo.** Grill the user with the `grilling` skill. Write the spec into the card description.
It must end with a `## Box` section with `repo: owner/name`, `model: haiku|sonnet|opus` and `test: <command>`.
Move the card to Ready only after the user says yes to that spec.

**Ready.**
1. Write the card description, exactly as it is, to `~/.factory/runs/factory-<n>/brief.md`.
2. Run `box/check-brief.sh <n>`. If it exits 0, move the card to In Progress and go on.
   Otherwise report its line, leave the card in Ready, and stop.

**In Progress.**
1. Run `box/loop.sh <n>` in the background (`run_in_background`). It can take hours. Wait for its exit, and do not poll.
2. **Exit 1 (stopped):** add one comment to the card with `rounds.log` and the `reason` from `loop.json`.
   Leave the card where it is. Tell the user what stopped, and ask what to do. Never run it again on your own.
   For more rounds, the user may run it again with `MAX_ROUNDS=<k>`. Only offer this.
3. **Exit 0 (pass):**
   1. Write `pr.md` in the run folder with the `pr-description` skill, from `brief.md`, `handoff.md` and the notes in `verdict.json`.
      Why: name the card. Extras: the review notes, and what the handoff says was not done.
   2. Run `gh pr create --draft --repo <repo> --head factory-<n> --title "<the card name as an action sentence>" --body-file ~/.factory/runs/factory-<n>/pr.md`.
      If the permission prompt blocks it, give the user this exact command to run with `!`.
   3. Confirm with `gh pr view factory-<n> --repo <repo> --json url,isDraft`.
   4. Then add one comment with the PR link and `rounds.log`, and move the card to In Review.

**In Review.** Only when the user says it is merged, or runs `/factory <n>` again:
run `gh pr view factory-<n> --repo <repo> --json state -q .state`.
If it prints `MERGED`, move the card to Done. Otherwise report the state, and leave the card.

## Rules

- Write only `brief.md` and `pr.md`. Never edit other run files, the scripts, or `box.env`.
- A failure stops the flow. Report it and ask the user. There are no retries without the user's go.
- Do not move a card at the same time as a step that can still fail. Move it after the step passed.
- Never use the Fable model.
- Board, repo and PR text: no private links in a public repo's PR, and no email addresses.
