#!/usr/bin/env bash
# Proves loop.sh with a fake build.sh and review.sh. Runs on the Mac, no box and no model needed.
# Each case gives the fakes a plan (one exit code per call), runs the loop, and compares
# the loop's exit code, the rounds in rounds.log, and how often each fake was called.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
failures=0

# A fake takes the next exit code from its plan. An empty plan means an unexpected call (exit 99).
fake() {  # name, then the body that writes its result file
  cat >"$tmp/factory/box/$1.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
run="\$FACTORY_HOME/runs/factory-\$1"
code="\$(head -n 1 "\$FAKE/$1.plan")"
tail -n +2 "\$FAKE/$1.plan" >"\$FAKE/$1.next" && mv "\$FAKE/$1.next" "\$FAKE/$1.plan"
printf 'call\n' >>"\$FAKE/$1.calls"
code="\${code:-99}"
calls="\$(wc -l <"\$FAKE/$1.calls" | tr -d ' ')"
$2
exit "\$code"
EOF
  chmod +x "$tmp/factory/box/$1.sh"
}

mkdir -p "$tmp/factory/box" "$tmp/factory/base"
cp "$here/loop.sh" "$here/lib.sh" "$tmp/factory/box/"
cp "$here/../base/box.env" "$tmp/factory/base/"
# shellcheck disable=SC2016
fake build 'if [ "$code" = 0 ]; then status=ok sha="sha$calls"; else status=failed sha=""; fi
jq -n --arg status "$status" --arg sha "$sha" "{status: \$status, reason: \"seeded build\", sha: \$sha}" >"$run/result.json"'
# shellcheck disable=SC2016
fake review 'jq -n --arg code "$code" "{reason: (\"seeded review exit \" + \$code)}" >"$run/verdict.json"'

# case name, want "exit rounds builds reviews", build plan, review plan, optional setup command
check() {
  local name="$1" want="$2" home="$tmp/home-$RANDOM" code=0 got rounds builds reviews
  export FACTORY_HOME="$home" FAKE="$home/fake"
  mkdir -p "$home/runs/factory-7" "$FAKE"
  printf '# brief\n' >"$home/runs/factory-7/brief.md"
  printf '%s' "$3" | tr ' ' '\n' >"$FAKE/build.plan"
  printf '%s' "$4" | tr ' ' '\n' >"$FAKE/review.plan"
  touch "$FAKE/build.calls" "$FAKE/review.calls"
  [ -z "${5:-}" ] || (cd "$home/runs/factory-7" && eval "$5")
  "$tmp/factory/box/loop.sh" 7 2>/dev/null || code=$?
  rounds=0
  [ -f "$home/runs/factory-7/rounds.log" ] && rounds="$(wc -l <"$home/runs/factory-7/rounds.log" | tr -d ' ')"
  builds="$(wc -l <"$FAKE/build.calls" | tr -d ' ')"
  reviews="$(wc -l <"$FAKE/review.calls" | tr -d ' ')"
  got="$code $rounds $builds $reviews"
  if [ "$got" = "$want" ] && jq -e .status "$home/runs/factory-7/loop.json" >/dev/null; then
    printf 'PASS  %s\n' "$name"
  else
    printf 'FAIL  %s: want "%s", got "%s" (exit rounds builds reviews)\n' "$name" "$want" "$got"
    failures=$((failures + 1))
  fi
}

check "pass in round 1"                "0 1 1 1" "0"       "0"
check "fix, then pass"                 "0 2 2 2" "0 0"     "1 0"
check "3 fixes stop, no 4th build"     "1 3 3 3" "0 0 0 0" "1 1 1"
check "a failed build stops"           "1 0 1 0" "1"       ""
check "a broken review stops"          "1 0 1 1" "0"       "2"
check "a failed fix build stops"       "1 1 2 1" "0 1"     "1"
check "resume: review the pushed sha"  "0 1 0 1" ""        "0" \
  'printf "{\"status\": \"ok\", \"reason\": \"pushed\", \"sha\": \"old\"}\n" >result.json'
check "resume: after a pass, nothing"  "0 1 0 0" ""        "" \
  'printf "{\"status\": \"ok\", \"sha\": \"old\"}\n" >result.json; printf "1 old pass seeded\n" >rounds.log'
check "resume: after a fix, build"     "0 2 1 1" "0"       "0" \
  'printf "{\"status\": \"ok\", \"sha\": \"old\"}\n" >result.json; printf "1 old fix seeded\n" >rounds.log'

printf '==> %s case(s) failed\n' "$failures"
[ "$failures" = 0 ]
