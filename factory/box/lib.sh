# shellcheck shell=bash
# Helpers shared by build.sh and review.sh. Runs on the Mac.
# The caller defines refuse() (stop before any box: exit 2) and fail() (stop after a box started),
# then sources this file and calls load_card <n>.

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../base/box.env
. "$here/../base/box.env"

step() { echo "==> $*" >&2; }

# Sets key, run and brief for card <n>.
load_card() {
  [[ "${1:-}" =~ ^[0-9]+$ ]] || { echo "usage: $(basename "$0") <card number>" >&2; exit 2; }
  key="factory-$1"
  run="${FACTORY_HOME:-$HOME/.factory}/runs/$key"
  brief="$run/brief.md"
  [ -f "$brief" ] || { echo "no brief at $brief" >&2; exit 2; }
}

# A value from the brief's "## Box" section, for example `repo: owner/name`.
box_field() {
  awk -v k="$1: " '
    /^## / { inside = ($0 ~ /^## Box[[:space:]]*$/) }
    inside && index($0, k) == 1 { print substr($0, length(k) + 1); exit }
  ' "$brief"
}

# Sets repo, model and test_cmd from the brief, and refuses a brief without a valid repo or test.
read_box_section() {
  repo="$(box_field repo)"
  model="$(box_field model)"
  model="${model:-sonnet}"
  test_cmd="$(box_field test)"
  [[ "$repo" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || refuse "the Box section has no valid 'repo: owner/name' line"
  [ -n "$test_cmd" ] || refuse "the Box section has no 'test:' line"
  case "$model" in haiku | sonnet | opus) ;; *) refuse "model must be haiku, sonnet or opus, not '$model'" ;; esac
}

# Refuses when one of the named boxes exists, when the box cap is reached, or below the disk floor
# (Docker has no disk limit per box).
guard_room() {  # box names that must not exist yet
  local name running free_gib
  for name in "$@"; do
    docker inspect "$name" >/dev/null 2>&1 && refuse "box $name already exists: another run of this card is going"
  done
  running="$(docker ps --format '{{.Names}}' | grep -cE '^factory-[0-9]+(-push)?$' || true)"
  [ "$running" -lt "$BOX_CAP" ] || refuse "$running factory boxes are running, the cap is $BOX_CAP"
  free_gib="$(df -k "$HOME" | awk 'NR == 2 { print int($4 / 1048576) }')"
  [ "$free_gib" -ge "$MIN_FREE_GIB" ] || refuse "only ${free_gib} GiB free disk, the floor is $MIN_FREE_GIB GiB"
  docker image inspect "$IMAGE" >/dev/null 2>&1 || refuse "image $IMAGE not found, build it from factory/base"
}

# Tokens stay in shell variables on the Mac. They reach a box only through stdin, never argv or disk.
load_tokens() {
  github_token="$(security find-generic-password -s factory-github -w)" || refuse "no factory-github token in the keychain"
  claude_token="$(security find-generic-password -s factory-claude -w)" || refuse "no factory-claude token in the keychain"
  { [ -n "$github_token" ] && [ -n "$claude_token" ]; } || refuse "a keychain token is empty"
}

start_box() {
  docker run -d --name "$1" "${BOX_FLAGS[@]}" "$IMAGE" >/dev/null
  sleep 1
  [ "$(docker inspect -f '{{.State.Running}}' "$1")" = true ] || { docker logs "$1" >&2; fail "box $1 did not start"; }
}

# Runs a script in a box as the box user, with the GitHub token in GIT_TOKEN for this one process.
# git reads it through a credential helper that is passed with -c, so it is never stored in a git config.
with_github() {  # box script [docker exec flags...]
  local target="$1" script="$2"
  shift 2
  printf '%s\n' "$github_token" | docker exec -i -u agent -w /home/agent "$@" "$target" bash -c '
    read -r GIT_TOKEN; export GIT_TOKEN
    gitauth() { git -c credential.helper= -c "credential.helper=!f(){ echo username=x-access-token; echo \"password=\$GIT_TOKEN\"; }; f" "$@"; }
    set -euo pipefail
    '"$script"
}

# Runs claude -p in a box with the prompt from stdin, and prints its stream-json transcript.
# The Claude token is sent as the first stdin line. The session may print its own env,
# so every line is scrubbed of the token before it leaves this function.
run_claude() {  # box workdir model timeout tools system-prompt
  { printf '%s\n' "$claude_token"; cat; } |
    docker exec -i -u agent -w "$2" -e MODEL="$3" -e TIMEOUT="$4" -e TOOLS="$5" -e JOB="$6" \
      -e GIT_TERMINAL_PROMPT=0 "$1" bash -lc '
        read -r CLAUDE_CODE_OAUTH_TOKEN; export CLAUDE_CODE_OAUTH_TOKEN
        exec timeout "$TIMEOUT" claude -p --model "$MODEL" --append-system-prompt "$JOB" \
          --tools "$TOOLS" --strict-mcp-config --dangerously-skip-permissions \
          --output-format stream-json --verbose 2>&1
      ' |
    T="$claude_token" awk '{ while ((i = index($0, ENVIRON["T"])) > 0) $0 = substr($0, 1, i - 1) "[CLAUDE_TOKEN]" substr($0, i + length(ENVIRON["T"])); print }'
}
