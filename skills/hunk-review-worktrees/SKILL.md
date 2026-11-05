---
name: hunk-review-worktrees
description: Open a git worktree's commits and diffs in a Herdr app pane beside the agent using hunk, one pane per worktree. Use when the user asks to see, review, or diff what an agent or branch produced in a worktree, or asks which worktrees have new work.
---

# Review worktrees

Show the user what each parallel git worktree added, and open each one for
reading in its own pane beside the agent. Two tools do the work: the
**Herdr app** (`herdr-app`) holds the pane, **hunk** renders the commits and diffs.

## When to use this

- "What did the agents produce?" / "which worktrees have new commits?"
- "Show me what agent-a did" / "open the diff for that branch"
- After you have finished work in a worktree and the user should review it.

## The one constraint that shapes everything

`hunk log` has **no `--repo`, `-C` or `--cwd` flag**. It resolves the repository
from its own process directory. `pane.split` takes a command but no folder,
so the pane runs `sh -c 'cd <worktree> && exec hunk log <range>'`. Never try to
pass the repo to hunk as an argument — there is no such argument.

## Step 1 — find the worktrees

```bash
git worktree list --porcelain | sed -n 's/^worktree //p'
```

**Parse by line prefix, never with `awk '{print $2}'`.** A worktree at
`/Users/me/My Projects/repo` is one line; splitting on whitespace truncates it
to `/Users/me/My`, and the worktree silently disappears from your answer.

The first entry is the main checkout. Usually the user means the *linked*
worktrees — the ones an agent created. A worktree is the main one when its
`--git-dir` equals its `--git-common-dir`:

```bash
[ "$(git -C "$wt" rev-parse --path-format=absolute --git-dir)" \
  = "$(git -C "$wt" rev-parse --path-format=absolute --git-common-dir)" ]
```

If the user named specific paths, use exactly those and skip discovery.

## Step 2 — resolve the base branch

"What this worktree adds" means `<base>..HEAD`. Resolve base in this order, and
stop at the first that works:

1. `git -C "$wt" symbolic-ref -q --short refs/remotes/origin/HEAD`
   — **then verify it resolves**:
   `git -C "$wt" rev-parse --verify -q "<ref>^{commit}"`
2. `origin/main`
3. `origin/master`
4. `main`
5. `master`
6. `HEAD` — degenerate; the count will be 0, which is honest rather than wrong.

Step 1's verification is not optional. A stale `origin/HEAD` left pointing at a
deleted branch makes every range empty, so every worktree reports "0 new
commits" and nothing on screen says the base is broken.

Do not assume `main`. Plenty of repositories still default to `master`.

## Step 3 — count what each one added

```bash
git -C "$wt" rev-list --count "$base..HEAD"
```

Report this per worktree. **Show zero-commit worktrees too** — "the agent did
nothing" and "the worktree is missing" are different facts, and the user needs
to tell them apart. Say which base you used; if the count looks wrong to the
user, a wrong base is the usual cause.

A good summary looks like:

```
agent-retry   3 new   base:origin/master
agent-docs    1 new   base:origin/master
agent-idle    0 new   base:origin/master
```

## Step 4 — open each one in a pane

Split **your own pane** (the agent's) to the right. The app knows you by your
terminal, `$HC_TERMINAL_ID`; find its pane with `herdr-app ls`. If
`HC_TERMINAL_ID` is not set, you are not in the Herdr app: do not split
anything, and tell the user to run `cd <worktree> && hunk log <base>..HEAD`
themselves.

If more than one worktree has new commits, open **one pane per worktree**.
Skip worktrees with 0 new commits, but keep them in the summary.
The first pane goes to the right of yours. Each next one splits the previous
review pane **down**, so the columns do not get too narrow.

```bash
ME=$(herdr-app ls | jq -r --arg t "$HC_TERMINAL_ID" \
  '.spaces[] | select(.machine == null) | .tabs[].terminals[] | select(.terminal == $t) | .pane')
# hunk runs inside the worktree, on the new commits only.
ARGV=$(jq -cn --arg wt "$WORKTREE" --arg range "$base..HEAD" \
  '["sh", "-c", "cd \"$1\" && exec hunk log \"$2\"", "hunk", $wt, $range]')

# The first worktree: right of your pane. Each next one: --direction down --pane "$PANE".
CREATED=$(herdr-app do pane.split --direction right --pane "$ME" --argv "$ARGV")
PANE=$(printf '%s' "$CREATED" | jq -r '.pane')
# The new pane takes the keyboard; give it back to your pane.
herdr-app do pane.focus --pane "$ME"
```

Keep the `PANE` ids. Tell the user which pane shows which worktree.

Always pass the `$base..HEAD` range. Plain `hunk log` shows the whole repo
history, and the new work gets lost in it. The range depends on the base from
Step 2, so verify the base first: a wrong base hides commits or shows old ones.
Use plain `hunk log` only when the user asks for the full history.

## Step 5 — tell the user how to drive it

They are about to get an interactive TUI. Say so, and name the keys:

- **↑ ↓** move, **Enter** opens the selected commit's diff
- **q** goes back from the diff to the commit list
- **q** again exits the browser and closes its pane
- **r** refreshes — new commits do not appear on their own, there is no watch mode
- **/** searches

## Reusing and closing panes

Panes add up and take space from the chat. If you already opened a pane for a
worktree in this session and it is still open, do not open a second one: tell
the user to press **r** in it. The pane closes itself when hunk exits. Close
the ones still open once the user is done reviewing:

```bash
herdr-app do pane.close --pane "$PANE"
```

## Gotchas

- **No watch mode.** `hunk log` has no `--watch`; that flag exists only on the
  review commands. If an agent commits while the browser is open, the user must
  press `r`.
- **A pane needs a terminal.** `hunk log` is interactive. To read commits
  yourself instead of showing them, use `hunk log --static --oneline` or plain
  `git log` — do not open a pane just to read output back.
- **Paths with spaces** survive if you quote every variable and parse as above.
- **`--cwd` needs a directory that exists.** A removed worktree still appears in
  a stale listing, so check the path exists before creating the pane.
- **Check the Herdr app is there.** These commands need the app running; without
  it, `herdr-app do` prints `{ "error": ... }` and exits 1. Then fall back to
  telling the user to run `cd <worktree> && hunk log` themselves.
