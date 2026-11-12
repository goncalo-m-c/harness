#!/usr/bin/env bash
# Proves that a box started from the factory image is safe. Runs on the Mac.
# It starts a throwaway box with the settings from box.env, runs every check,
# prints one PASS/FAIL line per check, removes the box (also when a check fails),
# and exits 1 if any check failed.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=box.env
. "$here/box.env"

docker image inspect "$IMAGE" >/dev/null 2>&1 || { echo "image $IMAGE not found. Build it with: docker build -t $IMAGE $here" >&2; exit 1; }

box="factory-check-$$"
failures=0

cleanup() { docker rm -f "$box" >/dev/null 2>&1 || true; }
trap cleanup EXIT

pass() { echo "PASS  $1"; }
fail() { echo "FAIL  $1: $2"; failures=$((failures + 1)); }
# Runs a command in the box the way the box runner will: as the box user, in a login shell.
in_box() { docker exec -u agent "$box" bash -lc "$1"; }
in_box_root() { docker exec -u root "$box" bash -c "$1"; }
label() { docker image inspect "$IMAGE" --format "{{index .Config.Labels \"$1\"}}"; }
bytes() {  # 2g -> 2147483648, 512m -> 536870912
  local n="${1%[gGmMkK]}"
  case "$1" in
    *[gG]) echo $((n * 1024 * 1024 * 1024)) ;;
    *[mM]) echo $((n * 1024 * 1024)) ;;
    *[kK]) echo $((n * 1024)) ;;
    *) echo "$n" ;;
  esac
}

echo "==> start box $box from $IMAGE"
docker run -d --name "$box" "${BOX_FLAGS[@]}" "$IMAGE" sleep infinity >/dev/null
sleep 1
[ "$(docker inspect -f '{{.State.Running}}' "$box")" = true ] || { echo "the box did not start:" >&2; docker logs "$box" >&2; exit 1; }

# 1. No Mac files and no mounts.
name="1 no Mac files"
mounts="$(docker inspect -f '{{len .Mounts}}' "$box")"
if [ "$mounts" != 0 ]; then
  fail "$name" "$mounts mount(s) in the box"
elif ! in_box 'test ! -e /Users' 2>/dev/null; then
  # Passes only when the box user really ran the test, so a failed docker exec cannot look like a pass.
  fail "$name" "/Users exists in the box, or the box user cannot run commands"
else
  pass "$name"
fi

# 2. The internet works for the hosts a task needs. Any HTTP answer counts.
name="2 internet"
down=""
for host in api.anthropic.com github.com pypi.org registry.npmjs.org; do
  code="$(in_box "curl -s -m 10 -o /dev/null -w '%{http_code}' https://$host" 2>/dev/null || true)"
  { [ -n "$code" ] && [ "$code" != 000 ]; } || down="$down $host"
done
if [ -n "$down" ]; then fail "$name" "no answer from:$down"; else pass "$name"; fi

# 3. No secrets in the box or in the image config.
name="3 no secrets"
token_re='^[A-Z0-9_]*(TOKEN|SECRET|API_KEY|PASSWORD)[A-Z0-9_]*='
found="$(in_box_root "find / -xdev \( -name .credentials.json -o -name .git-credentials \) 2>/dev/null" || true)"
image_env="$(docker image inspect "$IMAGE" --format '{{range .Config.Env}}{{println .}}{{end}}' | grep -iE "$token_re" | cut -d= -f1 || true)"
# The box user's env must really be read: a failed docker exec cannot look like "no tokens".
if ! user_env="$(in_box env 2>/dev/null)"; then
  fail "$name" "cannot read the box user's environment"
  user_env=""
fi
box_env="$(echo "$user_env" | grep -iE "$token_re" | cut -d= -f1 || true)"
if [ -z "$user_env" ]; then
  :  # already failed above
elif [ -n "$found" ]; then
  fail "$name" "credential files: $(echo "$found" | tr '\n' ' ')"
elif [ -n "$box_env$image_env" ]; then
  fail "$name" "token-like env vars: $(echo "$box_env $image_env" | tr '\n' ' ')"
else
  pass "$name"
fi

# 4. Each tool equals the version the image was built with (its label).
name="4 versions"
# A missing tool must give a FAIL line, not stop the script, so each lookup tolerates failure.
got_claude="$(in_box 'claude --version' 2>/dev/null | awk '{print $1}' || true)"
got_uv="$(in_box 'uv --version' 2>/dev/null | awk '{print $2}' || true)"
got_node="$(in_box 'node --version' 2>/dev/null || true)"
wrong=""
want="$(label factory.claude)"; [ -n "$want" ] && [ "$got_claude" = "$want" ] || wrong="$wrong claude=${got_claude:-none}(label ${want:-none})"
want="$(label factory.uv)";     [ -n "$want" ] && [ "$got_uv" = "$want" ]     || wrong="$wrong uv=${got_uv:-none}(label ${want:-none})"
want="$(label factory.node)";   [ -n "$want" ] && [ "$got_node" = "$want" ]   || wrong="$wrong node=${got_node:-none}(label ${want:-none})"
in_box 'git --version && npm --version' >/dev/null 2>&1 || wrong="$wrong git-or-npm-missing"
if [ -n "$wrong" ]; then fail "$name" "$wrong"; else pass "$name"; fi

# 5. The box user has no rights.
name="5 no privileges"
bad=""
[ "$(in_box whoami 2>/dev/null || true)" = agent ] || bad="$bad not-agent"
# PID 1 is the sleep the box started with; the second process comes from docker exec.
[ "$(in_box 'grep CapEff /proc/1/status' 2>/dev/null | cut -f2 || true)" = 0000000000000000 ] || bad="$bad pid1-has-capabilities"
[ "$(in_box 'grep CapEff /proc/self/status' 2>/dev/null | cut -f2 || true)" = 0000000000000000 ] || bad="$bad exec-has-capabilities"
[ "$(in_box 'grep NoNewPrivs /proc/1/status' 2>/dev/null | cut -f2 || true)" = 1 ] || bad="$bad pid1-can-gain-rights"
[ "$(in_box 'grep NoNewPrivs /proc/self/status' 2>/dev/null | cut -f2 || true)" = 1 ] || bad="$bad exec-can-gain-rights"
in_box 'command -v sudo || command -v su' >/dev/null 2>&1 && bad="$bad sudo-or-su-present"
# The tools the factory runs must not be the box user's to change, and no folder of the box user's may come
# before them on PATH. Otherwise a planted program runs in their place. Plain bash -c, the way the runner calls them.
for tool in claude git timeout; do
  path="$(docker exec -u agent "$box" bash -c "command -v $tool" 2>/dev/null || true)"
  if [ -z "$path" ] || docker exec -u agent "$box" bash -c "test -w '$path' || test -w '${path%/*}'" 2>/dev/null; then
    bad="$bad $tool-replaceable(${path:-missing})"
  fi
done
early="$(docker exec -u agent "$box" bash -c 'IFS=:; set -- $PATH; while [ $# -gt 1 ]; do case "$1" in /home/*) echo "$1" ;; esac; shift; done' 2>/dev/null || echo cannot-read-PATH)"
[ -z "$early" ] || bad="$bad user-folder-early-on-PATH($early)"
if [ -n "$bad" ]; then fail "$name" "$bad"; else pass "$name"; fi

# 6. The box has the limits from box.env.
name="6 limits applied"
bad=""
[ "$(docker inspect -f '{{.HostConfig.Memory}}' "$box")" = "$(bytes "$BOX_MEMORY")" ] || bad="$bad memory"
[ "$(docker inspect -f '{{.HostConfig.NanoCpus}}' "$box")" = "$((BOX_CPUS * 1000000000))" ] || bad="$bad cpus"
if [ -n "$bad" ]; then fail "$name" "$bad"; else pass "$name"; fi

echo "==> $failures check(s) failed"
[ "$failures" = 0 ]
