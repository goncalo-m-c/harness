#!/usr/bin/env bash
# Open a new herdr tab that shows a spec folder in glow (a TUI markdown viewer).
# Prints the folder instead when herdr, glow or jq is missing.
# Usage: open-spec-tab.sh <folder>
set -euo pipefail

folder="${1:?usage: open-spec-tab.sh <folder>}"
for tool in herdr glow jq; do
  command -v "$tool" >/dev/null 2>&1 || { echo "$folder"; exit 0; }
done
created="$(herdr tab create --cwd "$folder" --label "spec-$(basename "$folder")")"
pane="$(printf '%s' "$created" | jq -r '.result.root_pane.pane_id // empty')"
# The pane's own shell expands $(tput cols), so glow wraps at the new pane's width.
[ -n "$pane" ] && herdr pane run "$pane" "glow -p -w \$(( \$(tput cols) - 4 )) $(printf '%q' "$folder")" >/dev/null
echo "spec tab: $folder"
