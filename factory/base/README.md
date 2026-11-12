# factory-base

Every factory task runs in its own box. A box is a container started from one golden image, `factory-base`.
This folder builds that image and proves that a box started from it is safe.

## What is in the image

- Debian 13 slim (`trixie`), pinned by digest, arm64
- git, curl, Node 24 LTS, the Claude CLI and uv, at the versions pinned in the [`Dockerfile`](Dockerfile)
- one user, `agent`, with no `sudo` and no `su`
- the Claude auto-updater turned off

What is **not** in the image: any login, any token, `gh`, Docker.
A box gets its secrets only while a task runs, from the Mac.

## How a box protects the Mac

A box starts as root for one moment. The [entrypoint](entrypoint.sh) sets a firewall for outgoing traffic:

- DNS and the internet stay open
- the Mac and every private network are blocked: other containers, OrbStack machines, your home network

Then it runs the command as `agent` with **no capabilities**, and with `no_new_privs`, so no process can gain rights back.
`agent` cannot remove the firewall.

The firewall needs `NET_ADMIN` while the box starts.
A box started without it **does not start at all**, so there is never a box without its firewall.

How a box is started lives in [`box.env`](box.env): the image name, 2 GB of memory, 2 CPUs, and the flags every box needs.
Docker cannot limit disk space per container here, so boxes must be removed as soon as their task ends.

## Build it

You need [OrbStack](https://orbstack.dev) on an Apple Silicon Mac.

```sh
docker build -t factory-base factory/base
```

The first build takes about half a minute. Docker caches each step, so a later build redoes only what changed.
Add `--no-cache` to build everything from zero.

## Check it

```sh
factory/base/check-base.sh
```

It starts a throwaway box with the settings from `box.env`, runs seven checks the way the box runner works (`docker exec -u agent`), prints one PASS or FAIL line each, and removes the box.
It exits 1 if any check fails.

| Check | What it proves |
|---|---|
| 1 Mac localhost blocked | a listener on the Mac's `127.0.0.1` answers on the Mac, but not from the box through `host.docker.internal` or `0.250.250.254` |
| 2 no Mac files | the box has no mounts and no `/Users` |
| 3 internet | Anthropic, GitHub, PyPI and npm answer |
| 4 no secrets | no credential files, no token-like environment variables in the box or the image |
| 5 versions | every tool matches the version in the image labels |
| 6 no privileges | `agent` has no capabilities, cannot gain any, has no `sudo`/`su`, and cannot remove the firewall; the entrypoint gives the command `agent`'s own home, so a login shell finds `claude` |
| 7 fails closed, limits applied | a box without `NET_ADMIN` does not start; the box has the memory and CPU limits from `box.env` |

Each check passes only when the box really confirmed the good state.
A failure to run a command in the box is a FAIL, never a PASS.
Check 1 runs its positive control on the Mac first, and only a blocked connection (curl exit 7) counts.
To see the checks fail, run them against an image that is not a factory box:

```sh
IMAGE=debian:trixie-slim factory/base/check-base.sh   # 7 FAIL
```

## Upgrade a tool

1. Change the `ARG` default in the `Dockerfile`.
   For Node, also change `NODE_SHA256`. The Dockerfile says where to find it.
2. Build, then run the check.

To try a version once without editing the file:

```sh
docker build -t factory-base --build-arg CLAUDE_VERSION=2.2.0 factory/base
```

The check compares each tool with the image labels, so it also works for a build like this.

## The files

| File | Does |
|---|---|
| `Dockerfile` | the image: pinned base, tools, the `agent` user, labels with every pin |
| `entrypoint.sh` | the firewall, then the drop to `agent` with no rights |
| `box.env` | how a box is started, the runner limits and the commit author; any value can be overridden from the environment |
| `check-base.sh` | the seven checks |

## Not here yet

- An allowlist by domain, so a box can reach only the hosts a task needs
- More hardening, such as removing setuid bits from every binary
