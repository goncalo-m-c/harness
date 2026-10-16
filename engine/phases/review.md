# Review
**Goal:** Check the diff against the spec and the repo standards.
**Use:** agents `work-reviewer-spec` and `work-reviewer-standards`, in parallel.
**Agent:** `work-reviewer-spec`, `work-reviewer-standards`
**Subagent does:**
Review the diff `git -C {worktree} diff origin/main...HEAD` and its commits. Edit nothing except your report file.
- `work-reviewer-spec`: check the diff against `{store}/openspec/changes/{change}/`. Report path: `{store}/runs/{key}/reviews/spec.md`.
- `work-reviewer-standards`: check it against the rule files from `bash ~/.agents/skills/review-rules/scripts/select-rules.sh {worktree} origin/main`. Report path: `{store}/runs/{key}/reviews/standards.md`.
Write the report to your report path. Overwrite the file. Write nowhere else.
One finding per line: `- hard: path:line — what is wrong and the fix`, or `- soft: path:line — ...`. `hard` means it must be fixed.
If you find nothing, the file contains only `No findings.`
**Main does:**
1. Call `work_complete` with no evidence. The engine reads both reports and decides.
2. If it fails because of `hard` findings, read the reports. Send the findings to `work-implementer` with `work_task` (kind `edit`). Then dispatch both reviewers again.
3. If it fails because a report is missing or older than the last commit, dispatch that reviewer again.
4. If it passes, read both reports. Tell the user the result in a few lines, including the `soft` findings. Wait for `work_approve`.
**Write:** each reviewer writes its own report in `{store}/runs/{key}/reviews/`. The main window writes nothing.
**Gate:** `review_passed`. Both reports exist, are newer than the last commit, and have no `hard` finding. The user must approve the push.
**Never:**
- Never write or edit a report file yourself.
- Never call `work_approve` yourself.
