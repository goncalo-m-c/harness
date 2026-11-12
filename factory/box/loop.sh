#!/usr/bin/env bash
# Builds and reviews card <n> until the review passes, for at most MAX_ROUNDS rounds. Runs on the Mac.
#
#   loop.sh <n>
#
# A round is one review. rounds.log in the run folder gets one line per finished review:
#   <round> <sha> <pass|fix> <reason>
# It is the only round state, so a re-run continues where the last run stopped:
#   - the last line is a pass                     -> done
#   - result.json has a pushed sha with no line   -> review that sha first
#   - otherwise                                   -> build (a fix round when the branch exists)
# The loop stops at once on a failed build, a broken review, or when MAX_ROUNDS reviews were not a pass.
# Writes loop.json: {status: pass|stopped, reason, rounds, sha}.
# Exit 0: pass. Exit 1: stopped, ask the user. Exit 2: bad usage or no brief.
set -euo pipefail

finish() {  # status reason exit-code
  local rounds=0
  [ -f "$log" ] && rounds="$(wc -l <"$log" | tr -d ' ')"
  jq -n --arg status "$1" --arg reason "$2" --argjson rounds "$rounds" --arg sha "$(pushed_sha)" \
    '{status: $status, reason: $reason, rounds: $rounds, sha: $sha}' >"$run/loop.json"
  printf '==> loop %s: %s (%s round(s))\n' "$1" "$2" "$rounds" >&2
  exit "$3"
}
refuse() { finish stopped "$1" 1; }
fail() { finish stopped "$1" 1; }

# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"
load_card "${1:-}"
n="$1"
log="$run/rounds.log"

# The sha of the last successful push, or nothing.
pushed_sha() { jq -r 'select(.status == "ok") | .sha' "$run/result.json" 2>/dev/null || true; }
# The sha of the last review line, and its verdict.
last_field() { [ -f "$log" ] && tail -n 1 "$log" | cut -d ' ' -f "$1" || true; }

while true; do
  rounds=0
  [ -f "$log" ] && rounds="$(wc -l <"$log" | tr -d ' ')"
  [ "$(last_field 3)" = pass ] && finish pass "round $rounds passed the review" 0

  sha="$(pushed_sha)"
  if [ -n "$sha" ] && [ "$sha" != "$(last_field 2)" ]; then
    round=$((rounds + 1))
    step "round $round: review $sha"
    code=0
    "$here/review.sh" "$n" || code=$?
    reason="$(jq -r '.reason // "no reason"' "$run/verdict.json" 2>/dev/null || printf 'no verdict.json')"
    case "$code" in
      0) printf '%s %s pass %s\n' "$round" "$sha" "$reason" >>"$log" ;;
      1) printf '%s %s fix %s\n' "$round" "$sha" "$reason" >>"$log" ;;
      *) finish stopped "review exit $code: $reason" 1 ;;
    esac
    continue
  fi

  [ "$rounds" -lt "$MAX_ROUNDS" ] || finish stopped "$rounds round(s) used and the last review was not a pass" 1
  step "round $((rounds + 1)): build"
  code=0
  "$here/build.sh" "$n" || code=$?
  if [ "$code" != 0 ]; then
    reason="$(jq -r '.reason // "no reason"' "$run/result.json" 2>/dev/null || printf 'no result.json')"
    finish stopped "build exit $code: $reason" 1
  fi
done
