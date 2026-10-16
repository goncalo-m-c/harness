# CI
**Goal:** Get the PR checks green. Fix failures with the user's yes.
**Agent:** `work-ci-watcher`
**Subagent does:**
You are `work-ci-watcher`. Worktree: `{worktree}`. Branch: `{branch}`. Store: `{store}`. Key: `{key}`.
1. In `{worktree}`, run `gh pr checks --watch`. If CI still runs after about 20 minutes, stop and report `still running`.
2. Save `gh pr view --json headRefOid,statusCheckRollup` to `{store}/runs/{key}/ci/latest.json`. Raw, unedited.
3. If a check failed: read the failing logs (`gh run view <id> --log-failed`, tail only).
4. Write `{store}/runs/{key}/ci/NN.md` (next number): failing checks, root cause, proposed fix (files and change), confidence.
5. Report a summary of at most 10 lines.
**Main does:**
1. If green, call `work_complete`.
2. If red, show the user the proposed fix from the latest `ci/NN.md`. Ask for a yes.
3. On the user's explicit yes, call `work_task` (kind `edit`) with the fix. Then dispatch `work-pr` to push the new commit to `{branch}`. That yes also approves this push.
4. Dispatch `work-ci-watcher` again.
5. If still running, tell the user. Dispatch again on request.
**Write:** `{store}/runs/{key}/ci/latest.json` and `{store}/runs/{key}/ci/NN.md`
**Gate:** `ci_green`. `latest.json` is for the current `HEAD`. Every check is `SUCCESS`, `SKIPPED` or `NEUTRAL`.
**Never:**
- Never mark the PR ready for review.
- Never merge the PR.
- Never push without the user's yes to that fix.
- Never edit `ci/latest.json` by hand.
