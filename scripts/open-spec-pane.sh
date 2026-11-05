#!/usr/bin/env bash
# Open a Herdr app pane beside the agent's pane that shows a spec folder as markdown (the spec-viewer mod).
# Prints the folder instead when herdr-app, jq or the mod is missing, or when the agent does not run in the app.
# Usage: open-spec-pane.sh <folder>
set -euo pipefail

folder="${1:?usage: open-spec-pane.sh <folder>}"
fallback() { echo "$folder"; exit 0; }
command -v herdr-app >/dev/null 2>&1 && command -v jq >/dev/null 2>&1 || fallback
[ -n "${HC_TERMINAL_ID:-}" ] && [ -d "$HOME/.config/herdr-app/mods/spec-viewer" ] || fallback

# The app knows the agent by its terminal (HC_TERMINAL_ID); the split needs that terminal's pane.
pane="$(herdr-app ls | jq -r --arg t "$HC_TERMINAL_ID" \
  '.spaces[] | select(.machine == null) | .tabs[].terminals[] | select(.terminal == $t) | .pane')"
[ -n "$pane" ] || fallback

props="$(jq -cn --arg f "$folder" '{folder: $f}')"
spec="$(herdr-app do pane.split --direction right --pane "$pane" --mod spec-viewer --props "$props" | jq -r '.pane')"
# The new pane takes the keyboard; give it back to the agent.
herdr-app do pane.focus --pane "$pane" >/dev/null
# The agent closes it later with: herdr-app do pane.close --pane <id>
echo "spec pane $spec: $folder"
