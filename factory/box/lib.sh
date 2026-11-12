# shellcheck shell=bash
# Helpers shared by the box scripts. Runs on the Mac.
# The caller defines refuse() (stop before any box: exit 2) and fail() (stop after work started),
# then sources this file and calls load_card <n>.

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# How a box is started (image, limits, flags), then how the factory uses it.
# shellcheck source=../base/box.env
. "$here/../base/box.env"
# shellcheck source=box.env
. "$here/box.env"

step() { printf '==> %s\n' "$*" >&2; }

# Sets key, run and brief for card <n>.
load_card() {
  [[ "${1:-}" =~ ^[0-9]+$ ]] || { printf 'usage: %s <card number>\n' "$(basename "$0")" >&2; exit 2; }
  key="factory-$1"
  run="${FACTORY_HOME:-$HOME/.factory}/runs/$key"
  brief="$run/brief.md"
  [ -f "$brief" ] || { printf 'no brief at %s\n' "$brief" >&2; exit 2; }
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

# Refuses when the image is missing, one of the named boxes exists (another run of this card is going),
# or the box cap is reached.
guard_room() {  # box names that must not exist yet
  local boxes name running
  boxes="$(docker ps -a --format "{{.Names}}")" || refuse "Docker is not running"
  docker image inspect "$IMAGE" >/dev/null 2>&1 || refuse "no image $IMAGE, build it with: docker build -t $IMAGE factory/base"
  for name in "$@"; do
    grep -qx "$name" <<<"$boxes" && refuse "box $name already exists: another run of this card is going"
  done
  running="$(grep -cE '^factory-[0-9]+(-review)?$' <<<"$boxes" || true)"
  [ "$running" -lt "$BOX_CAP" ] || refuse "$running factory boxes exist, the cap is $BOX_CAP"
}

# The Claude token stays in a shell variable on the Mac. It reaches a box only through stdin.
load_claude_token() {
  claude_token="$(security find-generic-password -s factory-claude -w)" || refuse "no factory-claude token in the keychain"
  [ -n "$claude_token" ] || refuse "the factory-claude token in the keychain is empty"
}

# git on the Mac, with the user's own gh login as the only credential. gh hands the token to git
# through the credential protocol, so it is never in argv, in a git config, or in these scripts.
ghgit() { git -c credential.helper= -c 'credential.helper=!gh auth git-credential' "$@"; }

# Starts box <name> from the image, with <folder> mounted at /work. The caller deletes it on exit.
start_box() {  # name folder
  docker run -d --name "$1" "${BOX_FLAGS[@]}" -v "$2:/work" "$IMAGE" >/dev/null || fail "could not start box $1"
}

delete_box() { docker rm -f "$1" >/dev/null 2>&1 || true; }

# Runs a script in a box as the box user, in /work. Extra arguments become $1, $2... of the script.
# Values go in as arguments, which show up in the process list. Never pass a secret this way.
in_box() {  # box script [args...]
  local target="$1" script="$2"
  shift 2
  docker exec -i -u agent -w /work "$target" bash -c "set -euo pipefail; $script" _ "$@"
}

# Runs claude -p in a box with the prompt from stdin, and prints its stream-json transcript.
# The Claude token is sent as the first stdin line. The session may print its own env,
# so every line is scrubbed of the token before it leaves this function.
run_claude() {  # box workdir model timeout tools system-prompt
  # shellcheck disable=SC2016
  { printf '%s\n' "$claude_token"; cat; } |
    docker exec -i -u agent -w "$2" "$1" bash -c '
      read -r CLAUDE_CODE_OAUTH_TOKEN
      export CLAUDE_CODE_OAUTH_TOKEN GIT_TERMINAL_PROMPT=0
      exec timeout "$1" claude -p --model "$2" --append-system-prompt "$4" \
        --tools "$3" --strict-mcp-config --dangerously-skip-permissions \
        --output-format stream-json --verbose 2>&1
    ' _ "$4" "$3" "$5" "$6" |
    T="$claude_token" awk '{ while ((i = index($0, ENVIRON["T"])) > 0) $0 = substr($0, 1, i - 1) "[CLAUDE_TOKEN]" substr($0, i + length(ENVIRON["T"])); print }'
}
