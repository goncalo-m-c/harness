#!/usr/bin/env bash
# Start the engine container with the board tokens from the macOS keychain.
# Why: the tokens must not live in the user's shell or in Claude Code. They are exported only
# in this process, so they reach docker and the container and nothing else.
# Usage: run-engine.sh <root> <store> <harness>
set -euo pipefail

die() { printf '%s\n' "$*" >&2; exit 1; }

# Print the keychain secret of a service; print nothing when it is missing.
keychain_secret() { security find-generic-password -s "$1" -a "$USER" -w 2>/dev/null || true; }

# Export the variable VAR from the keychain service SERVICE, or warn and leave it empty.
load_token() {
  local var="$1" service="$2" value
  value="$(keychain_secret "$service")"
  if [ -z "$value" ]; then
    printf 'run-engine: no keychain item %s, so %s is empty and GitHub calls will fail\n' "$service" "$var" >&2
  fi
  export "$var=$value"
}

main() {
  [ "$#" -eq 3 ] || die "usage: run-engine.sh <root> <store> <harness>"
  local root="$1" store="$2" harness="$3" dir
  for dir in "$root" "$store" "$harness"; do
    [ -d "$dir" ] || die "run-engine: not a directory: $dir"
  done
  load_token WORK_BOARD_TOKEN factory-board
  load_token WORK_ISSUES_TOKEN factory-issues
  exec docker run -i --rm -v "$root:$root" -v "$store:$store" -e "WORK_STORE=$store" \
    -e WORK_PROJECT -e WORK_BOARD_TOKEN -e WORK_ISSUES_TOKEN \
    work-engine:0.1.0 python "$harness/engine/engine.py"
}

main "$@"
