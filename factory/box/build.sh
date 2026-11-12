#!/usr/bin/env bash
# Builds one card in a box and pushes branch factory-<n>. Runs on the Mac.
#
#   build.sh <n>     reads $FACTORY_HOME/runs/factory-<n>/brief.md (FACTORY_HOME defaults to ~/.factory)
#
# The brief is the card's approved spec. Its "## Box" section names the repo, the model and the test command.
# The box never talks to GitHub. The Mac clones and pushes with the user's gh login:
#   1. The Mac clones the repo into run/work and makes or takes branch factory-<n>.
#   2. Box factory-<n> gets run/work mounted at /work and the Claude token on stdin. The agent commits there.
#      The box streams out a git bundle of the new commits, then it is deleted.
#   3. The Mac never runs git in run/work again: the agent could have planted hooks or config there.
#      It fetches the bundle into a fresh clone and pushes. A plain push, never a force push: a fix round only
#      adds commits, so the push fails if anyone else moved the branch.
# Writes result.json, agent.jsonl, handoff.md and work.bundle to the run folder.
# Exit 0: pushed. Exit 1: the build failed and nothing was pushed. Exit 2: refused before any work started.
set -euo pipefail

sha=""
result() {  # status reason
  jq -n --arg status "$1" --arg reason "$2" --arg branch "$key" --arg sha "$sha" \
    '{status: $status, reason: $reason, branch: $branch, sha: $sha}' >"$run/result.json"
}
refuse() { result refused "$1"; printf 'build %s refused: %s\n' "$key" "$1" >&2; exit 2; }
fail() { result failed "$1"; printf 'build %s failed: %s (evidence in %s)\n' "$key" "$1" "$run" >&2; exit 1; }

# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"
load_card "${1:-}"
box="$key"
work="$run/work"
push="$run/push"

read_box_section
guard_room "$box"
load_claude_token

# Called by the EXIT trap below.
# shellcheck disable=SC2329
cleanup() { delete_box "$box"; rm -rf "$work" "$push"; }
trap cleanup EXIT

rm -rf "$run/result.json" "$run/agent.jsonl" "$run/handoff.md" "$run/work.bundle" "$work" "$push"

# ---- 1. Clone on the Mac ---------------------------------------------------------------------------------
step "clone $repo"
url="https://github.com/$repo.git"
ghgit clone -q "$url" "$work" || fail "clone of $repo failed"
default="$(git -C "$work" symbolic-ref --short refs/remotes/origin/HEAD)"
default="${default#origin/}"
# On a fix round factory-<n> already exists on GitHub: keep building on it.
# ls-remote --exit-code gives 2 when the branch is not there, anything else is an error.
remote=0
ghgit -C "$work" ls-remote --exit-code --heads origin "$key" >/dev/null || remote=$?
case "$remote" in
  0) round=fix; git -C "$work" switch -q "$key" ;;
  2) round=first; git -C "$work" switch -q -c "$key" ;;
  *) fail "could not read the branches of $repo" ;;
esac
git -C "$work" config user.name "$BOX_GIT_NAME"
git -C "$work" config user.email "$BOX_GIT_EMAIL"
cat >"$work/.git/hooks/commit-msg" <<'HOOK'
#!/bin/sh
grep -qi "^Co-Authored-By: Claude" "$1" || git interpret-trailers --in-place --trailer "Co-Authored-By: Claude <noreply@anthropic.com>" "$1"
HOOK
chmod +x "$work/.git/hooks/commit-msg"
# The commit the agent starts from, so the checks below count only the agent's new commits.
base="$(git -C "$work" rev-parse HEAD)"
step "$round round on $key, default branch $default"

# ---- 2. The agent in the box -----------------------------------------------------------------------------
step "start $box"
start_box "$box" "$work"

prompt="$(cat "$brief")"
if [ "$round" = fix ] && [ -f "$run/fixes.md" ]; then
  prompt="$prompt"$'\n\n## Fixes to make in this round\n\n'"$(cat "$run/fixes.md")"
fi
job="You build this task in a sandbox box. Do the tasks. One commit per task. Run \`$test_cmd\` and fix until it passes. Write ~/handoff.md: what you did, what you did not do. You cannot push: the factory pushes your commits. Never change .github/: the factory refuses to push it."

step "agent ($model, timeout $AGENT_TIMEOUT)"
agent_code=0
printf '%s\n' "$prompt" |
  run_claude "$box" /work "$model" "$AGENT_TIMEOUT" Bash,Read,Edit,Write,Glob,Grep "$job" \
    >"$run/agent.jsonl" || agent_code=$?
in_box "$box" 'cat ~/handoff.md' >"$run/handoff.md" 2>/dev/null || step "the agent wrote no handoff.md"
[ "$agent_code" = 0 ] || fail "the agent step exited $agent_code (124 means it hit the $AGENT_TIMEOUT timeout)"

step "check the agent's work"
# The scripts run in the box, so their variables must expand there, not here.
# shellcheck disable=SC2016
facts="$(in_box "$box" 'git rev-list --count "$1"..HEAD; git status --porcelain | wc -l' "$base")" ||
  fail "could not read the agent's work"
new="$(sed -n 1p <<<"$facts")"
dirty="$(sed -n 2p <<<"$facts" | tr -d ' ')"
[ "$new" -ge 1 ] 2>/dev/null || fail "the agent made no new commit"
[ "$dirty" = 0 ] || fail "the agent left uncommitted changes"
# The bundle is streamed out, so the Mac writes a file it owns instead of reading one from the mount.
# shellcheck disable=SC2016
in_box "$box" 'git bundle create -q - "$1"..HEAD' "$base" >"$run/work.bundle" || fail "could not bundle the agent's work"
delete_box "$box"

# ---- 3. Push from a fresh clone on the Mac ---------------------------------------------------------------
step "push $key"
ghgit clone -q "$url" "$push" || fail "the second clone of $repo failed"
git -C "$push" fetch -q "$run/work.bundle" "HEAD:refs/heads/$key" || fail "the bundle does not apply on $repo"
# GitHub runs what is in .github/ (workflows, actions) with the repo's secrets as soon as a branch is pushed,
# before any review. So the factory never pushes commits that change it. Only the branch tip counts:
# GitHub reads the workflows from the tip, so a file added and removed again does no harm.
ci="$(git -C "$push" diff --no-renames --name-only "$base" "refs/heads/$key" -- .github)" ||
  fail "could not list the files the agent changed"
[ -z "$ci" ] || fail "the agent's commits change ${ci//$'\n'/, }: GitHub would run them before review, so nothing was pushed"
ghgit -C "$push" push -q origin "refs/heads/$key:refs/heads/$key" || fail "the push failed (did $key move on GitHub?)"
sha="$(git -C "$push" rev-parse "refs/heads/$key")"

result ok "pushed"
step "pushed $key at $sha"
