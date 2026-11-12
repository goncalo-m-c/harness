#!/usr/bin/env bash
# Reviews the pushed branch factory-<n> in one box, then counts the votes. Runs on the Mac.
#
#   review.sh <n>     reads $FACTORY_HOME/runs/factory-<n>/brief.md, like build.sh
#
# Box factory-<n>-review: clone (the only token step; the box cannot push), then the brief's test.
# A failing test is a fix right away. Otherwise one claude session (sonnet, a dispatcher only) runs three
# factory-reviewer subagents (opus): round 1 blind, round 2 they vote on each other's findings.
# count.sh on the Mac checks every file again and decides. The rules live in skills/factory-review.
# Writes verdict.json, fixes.md (only on fix), review.jsonl, review-test.log and out/ to the run folder.
# Exit 0: pass. Exit 1: fix. Exit 2: broken or refused.
set -euo pipefail

sha="" test_exit=""
verdict() {  # verdict reason [counted json from count.sh]
  jq --arg verdict "$1" --arg reason "$2" --arg branch "$key" --arg sha "$sha" \
    --arg command "${test_cmd:-}" --arg exit "$test_exit" '
    {verdict: $verdict, reason: $reason, branch: $branch, sha_reviewed: $sha,
     test: {command: $command, exit: ($exit | tonumber? // null)}} + .
  ' <<<"${3:-"{\"fixes\": [], \"notes\": [], \"withdrawn\": [], \"raw\": {}}"}" >"$run/verdict.json"
}
refuse() { verdict refused "$1"; echo "review $key refused: $1" >&2; exit 2; }
fail() { verdict broken "$1"; echo "review $key broken: $1 (evidence in $run)" >&2; exit 2; }

# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"
load_card "${1:-}"
box="$key-review"

read_box_section
# A build of this card must not be running: it would change the branch under review.
guard_room "$box" "$key" "$key-push"
load_tokens

# Called by the EXIT trap below.
# shellcheck disable=SC2329
cleanup() { docker rm -f "$box" >/dev/null 2>&1 || true; }
trap cleanup EXIT

rm -rf "$run/verdict.json" "$run/fixes.md" "$run/review.jsonl" "$run/review-test.log" "$run/out"

step "start $box"
start_box "$box"

step "clone $key from $repo"
# The script runs in the box, so its variables must expand there, not here.
# shellcheck disable=SC2016
clone_out="$(with_github "$box" '
  gitauth ls-remote --exit-code --heads "https://github.com/$REPO.git" "$BRANCH" >/dev/null || { echo "no-branch"; exit 3; }
  gitauth clone -q --branch "$BRANCH" "https://github.com/$REPO.git" work
  cd work
  git remote set-url --push origin none
  default="$(git symbolic-ref --short refs/remotes/origin/HEAD | sed "s|^origin/||")"
  mkdir -p ~/review/out
  git diff "origin/$default...HEAD" >~/review/diff.patch
  echo "default=$default"
  echo "sha=$(git rev-parse HEAD)"
' -e REPO="$repo" -e BRANCH="$key")" || {
  grep -qx no-branch <<<"$clone_out" && refuse "branch $key is not on GitHub"
  fail "clone of $repo failed"
}
default="$(sed -n 's/^default=//p' <<<"$clone_out")"
sha="$(sed -n 's/^sha=//p' <<<"$clone_out")"

put_in_box() {  # local file, path in the box
  docker exec -i -u agent -e DEST="$2" "$box" bash -c 'mkdir -p "$(dirname "$DEST")" && cat >"$DEST"' <"$1" ||
    fail "could not copy $1 into the box"
}
put_in_box "$brief" /home/agent/review/brief.md
put_in_box "$here/review-check.sh" /home/agent/review/review-check.sh
put_in_box "$here/agents/factory-reviewer.md" /home/agent/.claude/agents/factory-reviewer.md
put_skills "$box" "$REVIEW_SKILLS"

step "test: $test_cmd"
test_exit=0
# shellcheck disable=SC2016
docker exec -u agent -w /home/agent/work -e TEST="$test_cmd" -e TIMEOUT="$TEST_TIMEOUT" "$box" \
  bash -lc 'timeout "$TIMEOUT" bash -c "$TEST"' >"$run/review-test.log" 2>&1 || test_exit=$?
put_in_box "$run/review-test.log" /home/agent/review/test.log
if [ "$test_exit" != 0 ]; then
  {
    echo "# Fixes from the review"
    echo
    echo "### tests: the test command fails"
    echo
    echo "\`$test_cmd\` exited $test_exit. The last 100 lines of its output:"
    echo
    echo '```'
    tail -n 100 "$run/review-test.log"
    echo '```'
  } >"$run/fixes.md"
  verdict fix "the test command exited $test_exit"
  step "fix: the test fails, no reviewers ran"
  exit 1
fi

step "review session (dispatcher sonnet, reviewers opus, timeout $REVIEW_TIMEOUT)"
dispatch="You run one factory review. The base ref is origin/$default. You only start reviewers and check their files.

1. In one message, start three factory-reviewer subagents at the same time. Their prompts:
   \"You are r1. Round 1. The base ref is origin/$default.\" and the same for r2 and r3.
2. When all three are done, run \`bash ~/review/review-check.sh ~/review/out/rK.round1.json 1 rK\` for r1, r2 and r3.
   If a check is not ok, start that reviewer once more, with the problems added to its prompt.
3. In one message, start three factory-reviewer subagents again, with \"Round 2\" instead of \"Round 1\".
4. Check the round-2 files the same way, with 2 instead of 1, and restart a reviewer once if needed.
5. Reply with one line: done."
job="You are the dispatcher in a factory review box. You never review code, never write or change a finding or vote, and never edit files."
session_code=0
printf '%s\n' "$dispatch" |
  run_claude "$box" /home/agent/review sonnet "$REVIEW_TIMEOUT" Agent,Bash,Read,Glob,Grep,Write,Skill "$job" \
    >"$run/review.jsonl" || session_code=$?
mkdir -p "$run/out"
docker exec -u agent "$box" tar -C /home/agent/review/out -cf - . | tar -C "$run/out" -xf - ||
  fail "could not copy the reviewers' files out of the box"
[ "$session_code" = 0 ] || fail "the review session exited $session_code (124 means it hit the $REVIEW_TIMEOUT timeout)"

# Model guard: the dispatcher is sonnet and every reviewer message is opus. Messages from a subagent
# carry parent_tool_use_id in the stream. No subagent message at all means no reviewer ran.
models="$(jq -r 'select(.type == "assistant") | "\(.parent_tool_use_id != null) \(.message.model)"' "$run/review.jsonl" | sort -u)"
grep -q '^true ' <<<"$models" || fail "no reviewer subagent message in the transcript"
bad_models="$(grep -vE '^(false claude-(opus|sonnet)-|true claude-opus-)' <<<"$models" || true)"
[ -z "$bad_models" ] || fail "unexpected models in the review: $(tr '\n' ' ' <<<"$bad_models")"

step "count the votes"
counted="$("$here/count.sh" "$run/out")" || fail "the reviewers' files are missing or break the shapes (see above)"
fixes="$(jq '.fixes | length' <<<"$counted")"
notes="$(jq '.notes | length' <<<"$counted")"

if [ "$fixes" = 0 ]; then
  verdict pass "no finding reached 2 of 3 ($notes note(s))" "$counted"
  step "pass ($notes note(s))"
  exit 0
fi

# Findings on the same aspect and place are grouped, so a problem that several reviewers kept shows once.
jq -r '"# Fixes from the review\n", (.fixes | group_by([.aspect, .file, .line])[] |
  "### \(.[0].aspect): \(.[0].file):\(.[0].line)\n", (.[] | "- \(.claim) (\(.id), agreed by \(.agreed_by | join(", ")))\n  Evidence: \(.evidence)"), "")' \
  <<<"$counted" >"$run/fixes.md"
verdict fix "$fixes finding(s) reached 2 of 3 ($notes note(s))" "$counted"
step "fix: $fixes finding(s), $notes note(s), see $run/fixes.md"
exit 1
