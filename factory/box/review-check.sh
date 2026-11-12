#!/usr/bin/env bash
# Checks one reviewer file against the shapes in skills/factory-review/SKILL.md.
#
#   review-check.sh <file> <round: 1|2> <reviewer: r1|r2|r3>
#
# A round-2 file is checked against the round-1 files in the same folder: one vote on every finding
# of the other two reviewers, and withdrawals of the reviewer's own findings only.
# Prints "ok" and exits 0, or prints one problem per line and exits 1.
# Runs in the review box (the reviewers check themselves) and on the Mac (count.sh trusts no box).
set -euo pipefail

file="${1:-}" round="${2:-}" id="${3:-}"
[[ "$id" =~ ^r[123]$ ]] || { echo "the reviewer id must be r1, r2 or r3"; exit 1; }
[[ "$round" =~ ^[12]$ ]] || { echo "the round must be 1 or 2"; exit 1; }
dir="$(dirname "$file")"

valid_json() {  # file
  [ -f "$1" ] || { echo "$1 is missing"; return 1; }
  jq -e 'type == "object"' "$1" >/dev/null 2>&1 || { echo "$1 is not a JSON object"; return 1; }
}
valid_json "$file" || exit 1

if [ "$round" = 1 ]; then
  problems="$(jq -r --arg id "$id" '
    def A: ["spec", "security", "quality", "tests"];
    def text: type == "string" and length > 0;
    [
      (if .reviewer != $id then "reviewer must be \"\($id)\"" else empty end),
      (if (.findings | type) != "array" then "findings must be a list" else
        (.findings[] | if type != "object" then "every finding must be an object" else
          (if (.id | type) != "string" or (.id | test("^" + $id + "-[0-9]+$") | not)
             then "finding id \(.id | tojson) must look like \($id)-1" else empty end),
          (if (.aspect | IN(A[]) | not) then "finding \(.id): aspect must be one of \(A | join(", "))" else empty end),
          (if (.file | text | not) then "finding \(.id): file must be a non-empty string" else empty end),
          (if (.line | type) != "number" or .line < 0 or (.line | floor) != .line
             then "finding \(.id): line must be a whole number, 0 or more" else empty end),
          (if (.claim | text | not) then "finding \(.id): claim is empty" else empty end),
          (if (.evidence | text | not) then "finding \(.id): evidence is empty" else empty end)
        end),
        ([.findings[] | objects | .id] | group_by(.) | map(select(length > 1))[] | "finding id \(.[0]) is used twice")
      end),
      (if (.clean_aspects | type) != "array" then "clean_aspects must be a list" else
        (.clean_aspects[] | select(IN(A[]) | not) | "clean_aspects has an unknown aspect \(tojson)"),
        ([.findings[]? | objects | .aspect] | unique) as $f | (.clean_aspects | unique) as $c |
        ((A - $f - $c)[] | "aspect \(.) is neither in a finding nor in clean_aspects"),
        (($f - ($f - $c))[] | "aspect \(.) is both in a finding and in clean_aspects")
      end)
    ] | .[]
  ' "$file")"
else
  own="$dir/$id.round1.json"
  valid_json "$own" >/dev/null || { echo "your round-1 file $own is missing or broken"; exit 1; }
  others=()
  for r in r1 r2 r3; do
    [ "$r" = "$id" ] && continue
    valid_json "$dir/$r.round1.json" >/dev/null || { echo "the round-1 file of $r is missing or broken"; exit 1; }
    others+=("$dir/$r.round1.json")
  done
  problems="$(jq -r --arg id "$id" --slurpfile own "$own" --slurpfile a "${others[0]}" --slurpfile b "${others[1]}" '
    def text: type == "string" and length > 0;
    ([$a[0], $b[0]] | map(.findings[]? | objects | .id)) as $want |
    ([$own[0].findings[]? | objects | .id]) as $mine |
    [
      (if .reviewer != $id then "reviewer must be \"\($id)\"" else empty end),
      (if (.votes | type) != "array" then "votes must be a list" else
        (.votes[] | if type != "object" then "every vote must be an object" else
          (if (.vote | IN("agree", "disagree") | not) then "vote on \(.id): vote must be agree or disagree" else empty end),
          (if (.reason | text | not) then "vote on \(.id): reason is empty" else empty end)
        end),
        ([.votes[] | objects | .id] as $v | $want[] | . as $w | ($v | map(select(. == $w)) | length) as $n |
          if $n == 0 then "no vote on \($w)" elif $n > 1 then "\($n) votes on \($w)" else empty end)
      end),
      (if (.withdraw | type) != "array" then "withdraw must be a list" else
        (.withdraw[] | select(IN($mine[]) | not) | "withdraw names \(tojson), which is not one of your findings")
      end)
    ] | .[]
  ' "$file")"
fi

if [ -n "$problems" ]; then
  echo "$problems"
  exit 1
fi
echo ok
