#!/usr/bin/env bash
# Checks that card <n>'s brief is ready for a box: it exists and its "## Box" section is valid.
# The main agent moves a card from Ready to In Progress only after this exits 0.
#
#   check-brief.sh <n>     prints "ok <repo> <model> <test>", or the problem and exit 2
set -euo pipefail

refuse() { printf 'brief %s refused: %s\n' "$key" "$1" >&2; exit 2; }
fail() { refuse "$1"; }

# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"
load_card "${1:-}"
read_box_section
printf 'ok %s %s %s\n' "$repo" "$model" "$test_cmd"
