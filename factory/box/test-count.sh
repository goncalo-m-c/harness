#!/usr/bin/env bash
# Proves the vote counting with seeded reviewer files. Runs on the Mac, no box and no model needed.
# Each case writes six files (3 reviewers x 2 rounds), runs count.sh, and compares the result.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
failures=0

# Round 1: reviewer with one security finding, or with none.
finding() { jq -n --arg r "$1" '{reviewer: $r, clean_aspects: ["spec", "quality", "tests"],
  findings: [{id: ($r + "-1"), aspect: "security", file: "a.sh", line: 3, claim: "token in argv", evidence: "line 3"}]}'; }
clean() { jq -n --arg r "$1" '{reviewer: $r, findings: [], clean_aspects: ["spec", "security", "quality", "tests"]}'; }
# Round 2: reviewer, then "id=vote" pairs; a pair "withdraw=id" withdraws an own finding.
votes() {
  local r="$1" pair votes="[]" withdraw="[]"
  shift
  for pair in "$@"; do
    if [ "${pair%%=*}" = withdraw ]; then
      withdraw="$(jq -c --arg id "${pair#*=}" '. + [$id]' <<<"$withdraw")"
    else
      votes="$(jq -c --arg id "${pair%%=*}" --arg v "${pair#*=}" '. + [{id: $id, vote: $v, reason: "seeded"}]' <<<"$votes")"
    fi
  done
  jq -n --arg r "$r" --argjson votes "$votes" --argjson withdraw "$withdraw" '{reviewer: $r, votes: $votes, withdraw: $withdraw}'
}

# case name, expected "fixes notes withdrawn" (or "exit 2"), then the six files in order
# r1.round1 r2.round1 r3.round1 r1.round2 r2.round2 r3.round2.
check() {
  local name="$1" want="$2" dir="$tmp/$1" got code=0
  mkdir -p "$dir"
  printf '%s\n' "$3" >"$dir/r1.round1.json"; printf '%s\n' "$4" >"$dir/r2.round1.json"; printf '%s\n' "$5" >"$dir/r3.round1.json"
  printf '%s\n' "$6" >"$dir/r1.round2.json"; printf '%s\n' "$7" >"$dir/r2.round2.json"; printf '%s\n' "$8" >"$dir/r3.round2.json"
  got="$("$here/count.sh" "$dir" 2>/dev/null)" || code=$?
  if [ "$code" != 0 ]; then
    got="exit $code"
  else
    got="$(jq -r '"\(.fixes | length) \(.notes | length) \(.withdrawn | length)"' <<<"$got")"
  fi
  if [ "$got" = "$want" ]; then echo "PASS  $name"; else echo "FAIL  $name: want '$want', got '$got'"; failures=$((failures + 1)); fi
}

F1="$(finding r1)" C2="$(clean r2)" C3="$(clean r3)"
check "3 of 3 agree: fix"     "1 0 0"  "$F1" "$C2" "$C3" "$(votes r1)" "$(votes r2 r1-1=agree)"    "$(votes r3 r1-1=agree)"
check "2 of 3 agree: fix"     "1 0 0"  "$F1" "$C2" "$C3" "$(votes r1)" "$(votes r2 r1-1=agree)"    "$(votes r3 r1-1=disagree)"
check "1 of 3 agree: note"    "0 1 0"  "$F1" "$C2" "$C3" "$(votes r1)" "$(votes r2 r1-1=disagree)" "$(votes r3 r1-1=disagree)"
check "withdrawn: dropped"    "0 0 1"  "$F1" "$C2" "$C3" "$(votes r1 withdraw=r1-1)" "$(votes r2 r1-1=agree)" "$(votes r3 r1-1=agree)"
check "own vote is ignored"   "0 1 0"  "$F1" "$C2" "$C3" "$(votes r1 r1-1=agree)" "$(votes r2 r1-1=disagree)" "$(votes r3 r1-1=disagree)"
check "no findings: clean"    "0 0 0"  "$(clean r1)" "$C2" "$C3" "$(votes r1)" "$(votes r2)" "$(votes r3)"
check "two findings agree"    "2 0 0"  "$F1" "$(finding r2)" "$C3" "$(votes r1 r2-1=agree)" "$(votes r2 r1-1=agree)" "$(votes r3 r1-1=disagree r2-1=disagree)"
check "missing vote: broken"  "exit 2" "$F1" "$C2" "$C3" "$(votes r1)" "$(votes r2 r1-1=agree)" "$(votes r3)"
check "double vote: broken"   "exit 2" "$F1" "$C2" "$C3" "$(votes r1)" "$(votes r2 r1-1=agree r1-1=agree)" "$(votes r3 r1-1=agree)"
check "foreign withdraw: broken" "exit 2" "$F1" "$C2" "$C3" "$(votes r1)" "$(votes r2 r1-1=agree withdraw=r1-1)" "$(votes r3 r1-1=agree)"
check "bad aspect: broken"    "exit 2" "$(jq '.findings[0].aspect = "style"' <<<"$F1")" "$C2" "$C3" "$(votes r1)" "$(votes r2 r1-1=agree)" "$(votes r3 r1-1=agree)"
check "aspect not covered: broken" "exit 2" "$(jq '.clean_aspects = ["spec"]' <<<"$F1")" "$C2" "$C3" "$(votes r1)" "$(votes r2 r1-1=agree)" "$(votes r3 r1-1=agree)"
check "empty file: broken"    "exit 2" "$F1" "$C2" "$C3" "$(votes r1)" "$(votes r2 r1-1=agree)" ""

echo "==> $failures case(s) failed"
[ "$failures" = 0 ]
