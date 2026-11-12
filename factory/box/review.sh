#!/usr/bin/env bash
# Reviews the pushed branch factory-<n> in one box, then counts the votes. Runs on the Mac.
#
#   review.sh <n>     reads $FACTORY_HOME/runs/factory-<n>/brief.md, like build.sh
#
# The Mac clones the branch into run/review-work and writes the diff, before any box exists.
# Box factory-<n>-review gets that clone mounted at /work. It has no GitHub login, so it cannot push.
# First the brief's test runs there. A failing test is a fix right away. Otherwise one claude session
# (sonnet, a dispatcher only) runs three factory-reviewer subagents (opus): round 1 blind, round 2 they
# vote on each other's findings. count.sh on the Mac checks every file again and decides.
# The rules live in skills/factory-review.
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
refuse() { verdict refused "$1"; printf 'review %s refused: %s\n' "$key" "$1" >&2; exit 2; }
fail() { verdict broken "$1"; printf 'review %s broken: %s (evidence in %s)\n' "$key" "$1" "$run" >&2; exit 2; }

# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"
load_card "${1:-}"
box="$key-review"
work="$run/review-work"

read_box_section
# A build of this card must not be running: it would change the branch under review.
guard_room "$box" "$key"
load_claude_token

# Called by the EXIT trap below.
# shellcheck disable=SC2329
cleanup() { delete_box "$box"; rm -rf "$work"; }
trap cleanup EXIT

rm -rf "$run/verdict.json" "$run/fixes.md" "$run/review.jsonl" "$run/review-test.log" "$run/out" "$work"

step "clone $key from $repo"
url="https://github.com/$repo.git"
remote=0
ghgit ls-remote --exit-code --heads "$url" "$key" >/dev/null || remote=$?
case "$remote" in
  0) ;;
  2) refuse "branch $key is not on GitHub" ;;
  *) fail "could not read the branches of $repo" ;;
esac
ghgit clone -q --branch "$key" "$url" "$work" || fail "clone of $repo failed"
default="$(git -C "$work" symbolic-ref --short refs/remotes/origin/HEAD)"
default="${default#origin/}"
sha="$(git -C "$work" rev-parse HEAD)"
git -C "$work" diff "origin/$default...HEAD" >"$run/diff.patch"

step "start $box"
start_box "$box" "$work"

put_in_box() {  # local file, path in the box
  # shellcheck disable=SC2016
  in_box "$box" 'mkdir -p "$(dirname "$1")" && cat >"$1"' "$2" <"$1" || fail "could not copy $1 into the box"
}
put_in_box "$brief" /home/agent/review/brief.md
put_in_box "$run/diff.patch" /home/agent/review/diff.patch
put_in_box "$here/review-check.sh" /home/agent/review/review-check.sh
put_in_box "$here/agents/factory-reviewer.md" /home/agent/.claude/agents/factory-reviewer.md
put_skills "$box" "$REVIEW_SKILLS"

step "test: $test_cmd"
test_exit=0
# shellcheck disable=SC2016
in_box "$box" 'timeout "$1" bash -c "$2"' "$TEST_TIMEOUT" "$test_cmd" >"$run/review-test.log" 2>&1 || test_exit=$?
put_in_box "$run/review-test.log" /home/agent/review/test.log
if [ "$test_exit" != 0 ]; then
  {
    printf '# Fixes from the review\n\n### tests: the test command fails\n\n'
    # The backticks are Markdown, not a command.
    # shellcheck disable=SC2016
    printf '`%s` exited %s. The last 100 lines of its output:\n\n```\n' "$test_cmd" "$test_exit"
    tail -n 100 "$run/review-test.log"
    printf '```\n'
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
# Each of the six files is streamed out by its known name, so the Mac writes only files it owns.
# A missing one stays missing, and count.sh makes the review broken.
mkdir -p "$run/out"
for name in r1.round1 r2.round1 r3.round1 r1.round2 r2.round2 r3.round2; do
  # shellcheck disable=SC2016
  in_box "$box" 'cat ~/review/out/"$1".json' "$name" >"$run/out/$name.json" 2>/dev/null || rm -f "$run/out/$name.json"
done
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
