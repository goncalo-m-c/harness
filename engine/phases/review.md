# Review
**Goal:** Check the diff against the spec and the repo standards.
**Use:** agents `work-reviewer-spec` and `work-reviewer-standards`, in parallel.
**Agent:** `work-reviewer-spec`, `work-reviewer-standards`
**Subagent does:**
Review the diff `git -C {worktree} diff origin/main...HEAD` and its commits. Edit nothing.
- `work-reviewer-spec`: check the diff against `{store}/openspec/changes/{change}/`.
- `work-reviewer-standards`: check it against the rule files from `bash ~/.agents/skills/review-rules/scripts/select-rules.sh {worktree} origin/main`.
Report each finding as `hard` or `soft`, with `path:line`.
**Main does:**
1. Merge both reports into one markdown text. Start with frontmatter `verdict: pass` or `verdict: fail`. Do not write any file yourself.
2. On `fail`, call `work_complete` with that markdown as `evidence`. The engine records it and the gate fails. Send the findings to `work-implementer` with `work_task` (kind `edit`). Then dispatch the reviewers again.
3. On `pass`, show the user the review. Call `work_complete` with the merged markdown as `evidence`. The engine writes the next `reviews/NN.md`. Wait for `work_approve`.
**Write:** the engine writes `{store}/runs/{key}/reviews/NN.md` from `evidence`
**Gate:** `review_passed`. The latest review file has `verdict: pass`. The user must approve the push.
**Never:**
- Never set `verdict: pass` while a `hard` finding is open.
- Never call `work_approve` yourself.
