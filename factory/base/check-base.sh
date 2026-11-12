#!/usr/bin/env bash
# Proves that a box started from the factory image is safe. Runs on the Mac.
# It starts a throwaway box with the settings from box.env, runs every check,
# prints one PASS/FAIL line per check, removes the box (also when a check fails),
# and exits 1 if any check failed.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=box.env
. "$here/box.env"

docker image inspect "$IMAGE" >/dev/null 2>&1 || { printf '%s\n' "image $IMAGE not found. Build it with: docker build -t $IMAGE $here" >&2; exit 1; }

box="factory-check-$$"
port=$((50000 + RANDOM % 10000))
listener=""
failures=0

cleanup() {
  if [ -n "$listener" ]; then
    pkill -P "$listener" 2>/dev/null || true
    kill "$listener" 2>/dev/null || true
  fi
  docker rm -f "$box" >/dev/null 2>&1 || true
}
trap cleanup EXIT

pass() { printf '%s\n' "PASS  $1"; }
fail() { printf '%s\n' "FAIL  $1: $2"; failures=$((failures + 1)); }
# Runs a command in the box the way the box runner will: as the box user, in a login shell.
in_box() { docker exec -u agent "$box" bash -lc "$1"; }
in_box_root() { docker exec -u root "$box" bash -c "$1"; }
label() { docker image inspect "$IMAGE" --format "{{index .Config.Labels \"$1\"}}"; }
bytes() {  # 2g -> 2147483648, 512m -> 536870912
  local n="${1%[gGmMkK]}"
  case "$1" in
    *[gG]) printf '%s\n' "$((n * 1024 * 1024 * 1024))" ;;
    *[mM]) printf '%s\n' "$((n * 1024 * 1024))" ;;
    *[kK]) printf '%s\n' "$((n * 1024))" ;;
    *) printf '%s\n' "$n" ;;
  esac
}

printf '%s\n' "==> start box $box from $IMAGE"
docker run -d --name "$box" "${BOX_FLAGS[@]}" "$IMAGE" sleep infinity >/dev/null
sleep 1
[ "$(docker inspect -f '{{.State.Running}}' "$box")" = true ] || { printf '%s\n' "the box did not start:" >&2; docker logs "$box" >&2; exit 1; }

# 1. The Mac's 127.0.0.1 answers on the Mac (positive control) but not from the box.
# A blocked connection makes curl exit 7. Any other code (for example 127, curl missing) proves nothing.
( while true; do printf 'HTTP/1.0 200 OK\r\n\r\nok' | nc -l 127.0.0.1 "$port"; done ) >/dev/null 2>&1 &
listener=$!
disown "$listener"
sleep 0.5
name="1 Mac localhost blocked"
if [ "$(curl -s -m 3 "http://127.0.0.1:$port" || true)" != ok ]; then
  fail "$name" "the positive control failed: the Mac listener did not answer on the Mac"
else
  leaks=""
  for target in host.docker.internal 0.250.250.254; do
    code=0
    in_box "curl -s -m 5 -o /dev/null http://$target:$port" >/dev/null 2>&1 || code=$?
    [ "$code" = 7 ] || leaks="$leaks $target(curl exit $code)"
  done
  if [ -n "$leaks" ]; then fail "$name" "not blocked:$leaks"; else pass "$name"; fi
fi

# 2. No Mac files and no mounts.
name="2 no Mac files"
mounts="$(docker inspect -f '{{len .Mounts}}' "$box")"
if [ "$mounts" != 0 ]; then
  fail "$name" "$mounts mount(s) in the box"
elif ! in_box 'test ! -e /Users' 2>/dev/null; then
  # Passes only when the box user really ran the test, so a failed docker exec cannot look like a pass.
  fail "$name" "/Users exists in the box, or the box user cannot run commands"
else
  pass "$name"
fi

# 3. The internet works for the hosts a task needs. Any HTTP answer counts.
name="3 internet"
down=""
for host in api.anthropic.com github.com pypi.org registry.npmjs.org; do
  code="$(in_box "curl -s -m 10 -o /dev/null -w '%{http_code}' https://$host" 2>/dev/null || true)"
  { [ -n "$code" ] && [ "$code" != 000 ]; } || down="$down $host"
done
if [ -n "$down" ]; then fail "$name" "no answer from:$down"; else pass "$name"; fi

# 4. No secrets in the box or in the image config.
name="4 no secrets"
token_re='^[A-Z0-9_]*(TOKEN|SECRET|API_KEY|PASSWORD)[A-Z0-9_]*='
found="$(in_box_root "find / -xdev \( -name .credentials.json -o -name .git-credentials \) 2>/dev/null" || true)"
image_env="$(docker image inspect "$IMAGE" --format '{{range .Config.Env}}{{println .}}{{end}}' | grep -iE "$token_re" | cut -d= -f1 || true)"
# The box user's env must really be read: a failed docker exec cannot look like "no tokens".
if ! user_env="$(in_box env 2>/dev/null)"; then
  fail "$name" "cannot read the box user's environment"
  user_env=""
fi
box_env="$(printf '%s\n' "$user_env" | grep -iE "$token_re" | cut -d= -f1 || true)"
if [ -z "$user_env" ]; then
  :  # already failed above
elif [ -n "$found" ]; then
  fail "$name" "credential files: $(printf '%s\n' "$found" | tr '\n' ' ')"
elif [ -n "$box_env$image_env" ]; then
  fail "$name" "token-like env vars: $(printf '%s\n' "$box_env $image_env" | tr '\n' ' ')"
else
  pass "$name"
fi

# 5. Each tool equals the version the image was built with (its label).
name="5 versions"
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

# 6. The box user has no rights and cannot remove the firewall.
name="6 no privileges"
bad=""
[ "$(in_box whoami 2>/dev/null || true)" = agent ] || bad="$bad not-agent"
# PID 1 is the command the entrypoint started; the second process comes from docker exec.
[ "$(in_box 'grep CapEff /proc/1/status' 2>/dev/null | cut -f2 || true)" = 0000000000000000 ] || bad="$bad pid1-has-capabilities"
[ "$(in_box 'grep CapEff /proc/self/status' 2>/dev/null | cut -f2 || true)" = 0000000000000000 ] || bad="$bad exec-has-capabilities"
[ "$(in_box 'grep NoNewPrivs /proc/1/status' 2>/dev/null | cut -f2 || true)" = 1 ] || bad="$bad pid1-can-gain-rights"
[ "$(in_box 'grep NoNewPrivs /proc/self/status' 2>/dev/null | cut -f2 || true)" = 1 ] || bad="$bad exec-can-gain-rights"
in_box 'command -v sudo || command -v su' >/dev/null 2>&1 && bad="$bad sudo-or-su-present"
# The command the entrypoint started must run with the box user's home, so a login shell finds claude.
[ "$(in_box 'tr "\\0" "\\n" < /proc/1/environ | grep "^HOME="' 2>/dev/null || true)" = HOME=/home/agent ] || bad="$bad pid1-home-not-agent"
docker run --rm "${BOX_FLAGS[@]}" "$IMAGE" bash -lc 'command -v claude' >/dev/null 2>&1 || bad="$bad entrypoint-login-shell-has-no-claude"
rules_before="$(in_box_root 'iptables -S OUTPUT | wc -l' 2>/dev/null || printf '0\n')"
in_box 'iptables -F' >/dev/null 2>&1 && bad="$bad agent-flushed-firewall"
rules_after="$(in_box_root 'iptables -S OUTPUT | wc -l' 2>/dev/null || printf '0\n')"
{ [ "$rules_before" -gt 1 ] && [ "$rules_after" = "$rules_before" ]; } || bad="$bad firewall-rules(before=$rules_before,after=$rules_after)"
if [ -n "$bad" ]; then fail "$name" "$bad"; else pass "$name"; fi

# 7. A box without its firewall rights does not start, and the box has the limits from box.env.
name="7 fails closed, limits applied"
bad=""
docker run --rm "$IMAGE" true >/dev/null 2>&1 && bad="$bad started-without-NET_ADMIN"
[ "$(docker inspect -f '{{.HostConfig.Memory}}' "$box")" = "$(bytes "$BOX_MEMORY")" ] || bad="$bad memory"
[ "$(docker inspect -f '{{.HostConfig.NanoCpus}}' "$box")" = "$((BOX_CPUS * 1000000000))" ] || bad="$bad cpus"
if [ -n "$bad" ]; then fail "$name" "$bad"; else pass "$name"; fi

printf '%s\n' "==> $failures check(s) failed"
[ "$failures" = 0 ]
