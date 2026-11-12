# factory-base

Every factory task runs in its own box. A box is a container started from one golden image, `factory-base`.
This folder builds that image and proves that a box started from it is safe.

## What is in the image

- Debian 13 slim (`trixie`), pinned by digest, arm64
- git, curl, jq, Node 24 LTS, the Claude CLI and uv, at the versions pinned in the [`Dockerfile`](Dockerfile)
- one user, `agent`, with no `sudo` and no `su`
- the Claude auto-updater turned off

What is **not** in the image: any login, any token, `gh`, Docker.
A box gets its secrets only while a task runs, from the Mac.

## How a box protects the Mac

A box runs as `agent` from its first process, with **no capabilities** and with `no_new_privs`, so no process can gain rights back.
It sees no Mac files except the one folder the box runner mounts at `/work`.

**The network is not isolated yet.** A box can reach the internet, and also the Mac and your local network.
The first version had a firewall for that. It was taken out to keep the factory simple while it is being built, and comes back as its own card.

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

It starts a throwaway box with the settings from `box.env`, runs six checks the way the box runner works (`docker exec -u agent`), prints one PASS or FAIL line each, and removes the box.
It exits 1 if any check fails.

| Check | What it proves |
|---|---|
| 1 no Mac files | the box has no mounts and no `/Users` |
| 2 internet | Anthropic, GitHub, PyPI and npm answer |
| 3 no secrets | no credential files, no token-like environment variables in the box or the image |
| 4 versions | every tool matches the version in the image labels |
| 5 no privileges | `agent` has no capabilities, cannot gain any, has no `sudo`/`su` |
| 6 limits applied | the box has the memory and CPU limits from `box.env` |

Each check passes only when the box really confirmed the good state.
A failure to run a command in the box is a FAIL, never a PASS.
To see the checks fail, run them against an image that is not a factory box:

```sh
IMAGE=debian:trixie-slim factory/base/check-base.sh   # FAIL lines
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
| `box.env` | how a box is started; any value can be overridden from the environment |
| `check-base.sh` | the six checks |

## Not here yet

- Network isolation: block the Mac and the local network again
- An allowlist by domain, so a box can reach only the hosts a task needs
- More hardening, such as removing setuid bits from every binary
