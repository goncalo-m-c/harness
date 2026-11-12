# The golden image for factory boxes. Every task box is a container started from it.
# Build:    docker build -t factory-base factory/base
# Override one pin for a single build:  --build-arg CLAUDE_VERSION=2.2.0
# Upgrade for good: change the ARG default here and build again.

# Pinned by digest, so the base cannot change under us.
ARG BASE_IMAGE=debian:trixie-slim@sha256:a72b4433de1cf7d6bae0c4cee74d0547f58601a643b3375f070c51600d63b6b2
# BASE_IMAGE is pinned by digest above, which is stricter than a tag.
# hadolint ignore=DL3006
FROM ${BASE_IMAGE}

ARG BASE_IMAGE
ARG CLAUDE_VERSION=2.1.322
ARG UV_VERSION=0.13.7
ARG NODE_VERSION=v24.22.3
# SHA256 of node-${NODE_VERSION}-linux-arm64.tar.xz, from https://nodejs.org/dist/${NODE_VERSION}/SHASUMS256.txt
ARG NODE_SHA256=6e51a2ada00f0011cc266f65d98922b403d7ad88f809ca2aa615a5fe1ce6e86c

# The check script compares each tool with these labels: what the image was really built with.
LABEL factory.base="${BASE_IMAGE}" \
      factory.claude="${CLAUDE_VERSION}" \
      factory.uv="${UV_VERSION}" \
      factory.node="${NODE_VERSION}"

SHELL ["/bin/bash", "-euo", "pipefail", "-c"]

# The digest-pinned base fixes the Debian release. Exact apt versions are not pinned: old ones disappear from the mirrors and break builds.
# hadolint ignore=DL3008
RUN apt-get update -qq \
 && apt-get install -y -qq --no-install-recommends git curl ca-certificates xz-utils jq >/dev/null \
 && rm -rf /var/lib/apt/lists/*

# slim has no sudo, but it ships su as setuid root. The box user must have no path to root.
RUN rm /usr/bin/su

# Node from the official archive. The build fails if the checksum does not match.
RUN archive="node-${NODE_VERSION}-linux-arm64.tar.xz" \
 && curl -fsSL -o "/tmp/${archive}" "https://nodejs.org/dist/${NODE_VERSION}/${archive}" \
 && echo "${NODE_SHA256}  /tmp/${archive}" | sha256sum --check --quiet \
 && tar -xJf "/tmp/${archive}" -C /usr/local --strip-components=1 \
      --exclude='*/share/doc' --exclude='*/CHANGELOG.md' --exclude='*/README.md' --exclude='*/LICENSE' \
 && rm "/tmp/${archive}"

RUN useradd --create-home --shell /bin/bash agent

# The box user's own tools. ~/.local/bin is on PATH for every process, and Debian's ~/.profile adds it for login shells.
USER agent
WORKDIR /home/agent
ENV PATH=/home/agent/.local/bin:${PATH} \
    DISABLE_AUTOUPDATER=1
RUN curl -fsSL https://claude.ai/install.sh | bash -s -- "${CLAUDE_VERSION}" >/dev/null
RUN curl -LsSf "https://astral.sh/uv/${UV_VERSION}/install.sh" | env UV_NO_MODIFY_PATH=1 sh >/dev/null

# The box runner mounts the repo at /work. ~/work points there, so prompts and skills can say ~/work.
RUN ln -s /work /home/agent/work

# A box runs as the box user from its first process: no root step, no entrypoint.
# It stays alive with `sleep infinity`; the box runner works in it with `docker exec -u agent`.
CMD ["sleep", "infinity"]
