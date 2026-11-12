#!/usr/bin/env bash
# Builds one card in a box and pushes branch factory-<n>. Runs on the Mac.
#
#   build.sh <n>     reads $FACTORY_HOME/runs/factory-<n>/brief.md (FACTORY_HOME defaults to ~/.factory)
#
# The brief is the card's approved spec. Its "## Box" section names the repo, the model and the test command.
# Two boxes keep the GitHub token away from the agent:
#   factory-<n>       clone (token), then the agent (no token), then the work is packed into a git bundle.
#                     The box is removed before any token step runs again, so nothing the agent started survives.
#   factory-<n>-push  a fresh box: clone (token), take in the bundle, rebase onto the default branch, push.
# Writes result.json, agent.jsonl, handoff.md and work.bundle to the run folder.
# Exit 0: pushed. Exit 1: the build failed and nothing was pushed. Exit 2: refused before any box started.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=../base/box.env
. "$here/../base/box.env"

n="${1:-}"
[[ "$n" =~ ^[0-9]+$ ]] || { echo "usage: build.sh <card number>" >&2; exit 2; }
key="factory-$n"
run="${FACTORY_HOME:-$HOME/.factory}/runs/$key"
brief="$run/brief.md"
box="$key"
push_box="$key-push"
sha=""

result() {  # status reason
  jq -n --arg status "$1" --arg reason "$2" --arg branch "$key" --arg sha "$sha" \
    '{status: $status, reason: $reason, branch: $branch, sha: $sha}' >"$run/result.json"
}
refuse() { result refused "$1"; echo "build $key refused: $1" >&2; exit 2; }
fail() { result failed "$1"; echo "build $key failed: $1 (evidence in $run)" >&2; exit 1; }
step() { echo "==> $*" >&2; }

# A value from the brief's "## Box" section, for example `repo: owner/name`.
box_field() {
  awk -v k="$1: " '
    /^## / { inside = ($0 ~ /^## Box[[:space:]]*$/) }
    inside && index($0, k) == 1 { print substr($0, length(k) + 1); exit }
  ' "$brief"
}

[ -f "$brief" ] || { echo "no brief at $brief" >&2; exit 2; }
repo="$(box_field repo)"
model="$(box_field model)"
model="${model:-sonnet}"
test_cmd="$(box_field test)"
[[ "$repo" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || refuse "the Box section has no valid 'repo: owner/name' line"
[ -n "$test_cmd" ] || refuse "the Box section has no 'test:' line"
case "$model" in haiku | sonnet | opus) ;; *) refuse "model must be haiku, sonnet or opus, not '$model'" ;; esac

# Guards: room for one more box, and enough free disk (Docker has no disk limit per box).
docker inspect "$box" >/dev/null 2>&1 && refuse "box $box already exists: another build of this card is running"
running="$(docker ps --format '{{.Names}}' | grep -cE '^factory-[0-9]+(-push)?$' || true)"
[ "$running" -lt "$BOX_CAP" ] || refuse "$running factory boxes are running, the cap is $BOX_CAP"
free_gib="$(df -k "$HOME" | awk 'NR == 2 { print int($4 / 1048576) }')"
[ "$free_gib" -ge "$MIN_FREE_GIB" ] || refuse "only ${free_gib} GiB free disk, the floor is $MIN_FREE_GIB GiB"
docker image inspect "$IMAGE" >/dev/null 2>&1 || refuse "image $IMAGE not found, build it from factory/base"

# Tokens stay in shell variables on the Mac. They reach a box only through stdin, never argv or disk.
github_token="$(security find-generic-password -s factory-github -w)" || refuse "no factory-github token in the keychain"
claude_token="$(security find-generic-password -s factory-claude -w)" || refuse "no factory-claude token in the keychain"
{ [ -n "$github_token" ] && [ -n "$claude_token" ]; } || refuse "a keychain token is empty"

cleanup() { docker rm -f "$box" "$push_box" >/dev/null 2>&1 || true; }
trap cleanup EXIT

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

mkdir -p "$run"
rm -f "$run/result.json" "$run/agent.jsonl" "$run/handoff.md" "$run/work.bundle"

# ---- Box 1: clone, agent, checks -------------------------------------------------------------------------
step "start $box"
start_box "$box"

step "clone $repo"
# On a fix round factory-<n> already exists on GitHub: clone it and keep building on it.
# BASE is the commit the agent starts from, so the check below counts only the agent's new commits.
# The script runs in the box, so its variables must expand there, not here.
# shellcheck disable=SC2016
clone_out="$(with_github "$box" '
  gitauth clone -q "https://github.com/$REPO.git" work
  cd work
  if gitauth ls-remote --exit-code --heads origin "$BRANCH" >/dev/null; then
    git switch -q "$BRANCH"; echo "round=fix"
  else
    git switch -q -c "$BRANCH"; echo "round=first"
  fi
  git config user.name "$NAME"; git config user.email "$EMAIL"
  cat >.git/hooks/commit-msg <<"HOOK"
#!/bin/sh
grep -qi "^Co-Authored-By: Claude" "$1" || git interpret-trailers --in-place --trailer "Co-Authored-By: Claude <noreply@anthropic.com>" "$1"
HOOK
  chmod +x .git/hooks/commit-msg
  echo "default=$(git symbolic-ref --short refs/remotes/origin/HEAD | sed "s|^origin/||")"
  echo "base=$(git rev-parse HEAD)"
' -e REPO="$repo" -e BRANCH="$key" -e NAME="$BOX_GIT_NAME" -e EMAIL="$BOX_GIT_EMAIL")" || fail "clone of $repo failed"
round="$(sed -n 's/^round=//p' <<<"$clone_out")"
default="$(sed -n 's/^default=//p' <<<"$clone_out")"
base="$(sed -n 's/^base=//p' <<<"$clone_out")"
step "$round round on $key, default branch $default"

prompt="$(cat "$brief")"
if [ "$round" = fix ] && [ -f "$run/fixes.md" ]; then
  prompt="$prompt"$'\n\n## Fixes to make in this round\n\n'"$(cat "$run/fixes.md")"
fi
job="You build this task in a sandbox box. Do the tasks. One commit per task. Run \`$test_cmd\` and fix until it passes. Write ~/handoff.md: what you did, what you did not do. You cannot push: the factory pushes your commits."

step "agent ($model, timeout $AGENT_TIMEOUT)"
# The Claude token is the first stdin line, the prompt is the rest. The agent may print its own env,
# so every line of the transcript is scrubbed of the token before it reaches the disk.
agent_code=0
{ printf '%s\n' "$claude_token"; printf '%s\n' "$prompt"; } |
  docker exec -i -u agent -w /home/agent/work -e JOB="$job" -e MODEL="$model" -e TIMEOUT="$AGENT_TIMEOUT" \
    -e GIT_TERMINAL_PROMPT=0 "$box" bash -lc '
      read -r CLAUDE_CODE_OAUTH_TOKEN; export CLAUDE_CODE_OAUTH_TOKEN
      exec timeout "$TIMEOUT" claude -p --model "$MODEL" --append-system-prompt "$JOB" \
        --tools Bash,Read,Edit,Write,Glob,Grep --strict-mcp-config --dangerously-skip-permissions \
        --output-format stream-json --verbose 2>&1
    ' |
  T="$claude_token" awk '{ while ((i = index($0, ENVIRON["T"])) > 0) $0 = substr($0, 1, i - 1) "[CLAUDE_TOKEN]" substr($0, i + length(ENVIRON["T"])); print }' \
    >"$run/agent.jsonl" || agent_code=$?
docker cp "$box:/home/agent/handoff.md" "$run/handoff.md" >/dev/null 2>&1 || step "the agent wrote no handoff.md"
[ "$agent_code" = 0 ] || fail "the agent step exited $agent_code (124 means it hit the $AGENT_TIMEOUT timeout)"

step "check the agent's work"
facts="$(docker exec -u agent -w /home/agent/work -e BASE="$base" "$box" bash -c '
  echo "new=$(git rev-list --count "$BASE"..HEAD)"
  echo "dirty=$(git status --porcelain | wc -l)"
  git bundle create -q /home/agent/work.bundle HEAD
')" || fail "could not read the agent's work"
docker cp "$box:/home/agent/work.bundle" "$run/work.bundle" >/dev/null
docker rm -f "$box" >/dev/null
[ "$(sed -n 's/^new=//p' <<<"$facts")" -ge 1 ] || fail "the agent made no new commit"
[ "$(sed -n 's/^dirty=//p' <<<"$facts" | tr -d ' ')" = 0 ] || fail "the agent left uncommitted changes"

# ---- Box 2: rebase and push, with no agent code inside ---------------------------------------------------
step "start $push_box"
start_box "$push_box"
docker cp "$run/work.bundle" "$push_box:/tmp/work.bundle" >/dev/null

step "rebase onto $default and push $key"
# Only refs/heads/factory-<n> is ever pushed. A fix round that was rebased needs a force push,
# so it is allowed with a lease: it fails if the branch moved on GitHub since this box cloned it.
# shellcheck disable=SC2016
push_out="$(with_github "$push_box" '
  gitauth clone -q "https://github.com/$REPO.git" work
  cd work
  git config user.name "$NAME"; git config user.email "$EMAIL"
  git fetch -q /tmp/work.bundle "HEAD:refs/heads/$BRANCH"
  git switch -q "$BRANCH"
  git rebase -q "origin/$DEFAULT" >/dev/null 2>&1 || { git rebase --abort; echo "conflict"; exit 3; }
  if lease="$(git rev-parse -q --verify "refs/remotes/origin/$BRANCH")"; then
    gitauth push -q --force-with-lease="refs/heads/$BRANCH:$lease" origin "HEAD:refs/heads/$BRANCH"
  else
    gitauth push -q origin "HEAD:refs/heads/$BRANCH"
  fi
  echo "sha=$(git rev-parse HEAD)"
' -e REPO="$repo" -e BRANCH="$key" -e DEFAULT="$default" -e NAME="$BOX_GIT_NAME" -e EMAIL="$BOX_GIT_EMAIL")" || {
  grep -qx conflict <<<"$push_out" && fail "the work conflicts with the latest $default"
  fail "the push failed"
}
sha="$(sed -n 's/^sha=//p' <<<"$push_out")"

result ok "pushed"
step "pushed $key at $sha"
