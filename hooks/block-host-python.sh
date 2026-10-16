#!/usr/bin/env bash
# PreToolUse(Bash): deny python/pip/uv/pytest on the host; allow them inside docker run/exec.
# Rule source: ~/.agents/rules/commands.md
set -euo pipefail

command="$(jq -r '.tool_input.command // empty')"
[ -n "$command" ] || exit 0

if printf '%s' "$command" | grep -Eq 'docker (run|exec)'; then
  exit 0
fi

# Command position: line start or after ; & | ( $( , optionally behind env/sudo/exec/timeout or VAR=value.
if printf '%s' "$command" | perl -0777 -ne 'exit(/(^|[;&|(]|\$\()\s*((env|sudo|exec|nohup|time|xargs)\s+(-\S+\s+)*|timeout\s+\S+\s+|[A-Za-z_][A-Za-z0-9_]*=\S*\s+)*(\S*\/)?(python[0-9.]*|pip[0-9.]*|uvx?|pytest)(\s|$)/m ? 0 : 1)'; then
  jq -n '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny",
    permissionDecisionReason: "Run python/uv/pytest inside Docker (rule: ~/.agents/rules/commands.md)."}}'
fi
