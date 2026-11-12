#!/usr/bin/env bash
# Counts the votes of one review. A script, not an LLM, decides what must be fixed.
#
#   count.sh <out folder with r1..r3.round1.json and r1..r3.round2.json>
#
# Rules (skills/factory-review/SKILL.md):
#   - a finding its author withdrew in round 2 is dropped
#   - the author counts as one agree; with at least one agree from the other two it is a fix, else a note
#   - votes on the reviewer's own findings, or on unknown ids, are ignored
# Prints {fixes, notes, withdrawn, raw}; every finding carries author and agreed_by.
# Exit 0 with the result, or exit 2 when any file is missing or breaks the shapes (a missing vote
# could turn a fix into a note, so the review is broken, never a pass).
set -euo pipefail

out="${1:?usage: count.sh <out folder>}"
here="$(cd "$(dirname "$0")" && pwd)"

broken=0
for round in 1 2; do
  for r in r1 r2 r3; do
    if ! problems="$("$here/review-check.sh" "$out/$r.round$round.json" "$round" "$r")"; then
      echo "$r round $round: $problems" | sed '2,$s/^/  /' >&2
      broken=1
    fi
  done
done
[ "$broken" = 0 ] || exit 2

jq -n \
  --slurpfile a1 "$out/r1.round1.json" --slurpfile a2 "$out/r2.round1.json" --slurpfile a3 "$out/r3.round1.json" \
  --slurpfile b1 "$out/r1.round2.json" --slurpfile b2 "$out/r2.round2.json" --slurpfile b3 "$out/r3.round2.json" '
  [$a1[0], $a2[0], $a3[0]] as $R1 |
  [$b1[0], $b2[0], $b3[0]] as $R2 |
  [$R2[] | .withdraw[]] as $withdrawn |
  [$R1[] | .reviewer as $author | .findings[] | . + {author: $author}] as $all |
  [$all[] | .id as $fid | .author as $author |
    . + {agreed_by: ([$author] + [$R2[] | select(.reviewer != $author) | .reviewer as $voter |
                     .votes[] | select(.id == $fid and .vote == "agree") | $voter])}] as $counted |
  {
    fixes: [$counted[] | select(.id | IN($withdrawn[]) | not) | select(.agreed_by | length >= 2)],
    notes: [$counted[] | select(.id | IN($withdrawn[]) | not) | select(.agreed_by | length < 2)],
    withdrawn: [$counted[] | select(.id | IN($withdrawn[]))],
    raw: {r1: {round1: $R1[0], round2: $R2[0]}, r2: {round1: $R1[1], round2: $R2[1]}, r3: {round1: $R1[2], round2: $R2[2]}}
  }
'
