---
name: harness-setup
description: Install the harness with the user, step by step. Follows the README install steps, then the notes for the user's tool in clients/. Run it from inside the harness repo.
disable-model-invocation: true
---

# Harness setup

Run this from inside the harness repo. Go one step at a time.
Show each command before you run it. Wait for the user's yes before you change anything outside this repo.

1. Ask which tool the user has. Only `claude` has notes now (`clients/claude.md`).
2. Ask for `STORE` and `ROOT` (see the notes). The repo root is `HARNESS`. Show the three paths and ask if they are fine.
3. Do step 1 of "Install" in `README.md`: build the image and create the store.
4. Do the steps in `clients/<tool>.md`, in order, with the user's paths.
   - Before a link, check that the target is not a real folder.
   - Before you touch `settings.json`, save a backup copy and show the user the exact change.
5. Tell the user to restart the tool. In the new session, go through the checks at the end of the notes. Ask for the result of each.

Never:
- Never run the push or merge tests yourself in one of the user's real repos.
- Never add `work_approve` to an allow list.
