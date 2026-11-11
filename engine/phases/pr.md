# PR
**Goal:** Push the branch, open a draft PR, and get the PR checks green. Fix failures with the user's yes.
**Use:** skill `pr-description`. Follow it as-is.
**Agent:** `work-pr`
**Subagent does:**
You are `work-pr`. Worktree: `{worktree}`. Branch: `{branch}`. Change folder: `{store}/openspec/changes/{change}/`. Store: `{store}`. Key: `{key}`.
1. Push: `git -C {worktree} push -u origin {branch}`.
2. If `gh pr view {branch}` finds a PR, go to step 4. Do not open a second PR.
3. Write the body from the spec goal and ticket, in the three sections of `pr-description`. When the run has an issue (`{issue}`, empty when none), end the body with `Closes {issue}`. Open the PR: `gh pr create --draft --head {branch}`.
4. If `{worktree}/.github/workflows` does not exist, report the PR URL and `no CI`. Stop.
5. In `{worktree}`, run `gh pr checks --watch`. If CI still runs after about 20 minutes, stop and report `still running`.
6. Save `gh pr view --json headRefOid,statusCheckRollup` to `{store}/runs/{key}/ci/latest.json`. Raw, unedited.
7. If a check failed, read the failing logs (`gh run view <id> --log-failed`, tail only).
8. Report the PR URL and the CI result: `green`, `red`, `still running` or `no CI`. For `red`, add the failing checks, their run ids and the likely cause, in at most 10 lines.
**Main does:**
1. Give the user the PR URL.
2. If CI is `green` or `no CI`, call `work_complete` with the PR URL as `evidence`.
3. If `red`, show the user the failing checks and the cause. Ask for a yes to fix them.
4. On the user's explicit yes, call `work_task` (kind `edit`) with the failing checks, run ids and cause. That yes also approves the push.
5. Dispatch `work-pr` again. It pushes the fix and watches CI again.
6. If `still running`, tell the user. Dispatch `work-pr` again on request.
**Write:** the draft PR on GitHub. `{store}/runs/{key}/ci/latest.json`.
**Gate:** `ci_green`. `refs/remotes/origin/{branch}` equals `HEAD`. If the repo has `.github/workflows`: `latest.json` is for `HEAD`, and every check is `SUCCESS`, `SKIPPED` or `NEUTRAL`.
**Never:**
- Never mark the PR ready for review.
- Never merge the PR.
- Never push to `main`.
- Never push a fix without the user's yes to that fix.
- Never edit `ci/latest.json` by hand.
