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

sha=""
result() {  # status reason
  jq -n --arg status "$1" --arg reason "$2" --arg branch "$key" --arg sha "$sha" \
    '{status: $status, reason: $reason, branch: $branch, sha: $sha}' >"$run/result.json"
}
refuse() { result refused "$1"; echo "build $key refused: $1" >&2; exit 2; }
fail() { result failed "$1"; echo "build $key failed: $1 (evidence in $run)" >&2; exit 1; }

# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"
load_card "${1:-}"
box="$key"
push_box="$key-push"

read_box_section
guard_room "$box" "$push_box"
load_tokens

cleanup() { docker rm -f "$box" "$push_box" >/dev/null 2>&1 || true; }
trap cleanup EXIT

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
put_skills "$box" "$BUILD_SKILLS"

prompt="$(cat "$brief")"
if [ "$round" = fix ] && [ -f "$run/fixes.md" ]; then
  prompt="$prompt"$'\n\n## Fixes to make in this round\n\n'"$(cat "$run/fixes.md")"
fi
job="You build this task in a sandbox box. Do the tasks. One commit per task. Run \`$test_cmd\` and fix until it passes. Write ~/handoff.md: what you did, what you did not do. You cannot push: the factory pushes your commits."

step "agent ($model, timeout $AGENT_TIMEOUT)"
agent_code=0
printf '%s\n' "$prompt" |
  run_claude "$box" /home/agent/work "$model" "$AGENT_TIMEOUT" Bash,Read,Edit,Write,Glob,Grep,Skill "$job" \
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
