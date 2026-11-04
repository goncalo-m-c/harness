# Runtime only. engine.py is mounted, not copied, so edits need no rebuild.
# Node comes from the official image: openspec needs Node 20+, Debian ships 18.
FROM node:22-bookworm-slim AS openspec
RUN npm install -g @fission-ai/openspec@1.14.2

FROM ghcr.io/astral-sh/uv:python3.12-bookworm-slim
COPY --from=openspec /usr/local/bin/node /usr/local/bin/node
COPY --from=openspec /usr/local/lib/node_modules /usr/local/lib/node_modules
RUN ln -s /usr/local/lib/node_modules/@fission-ai/openspec/bin/openspec.js /usr/local/bin/openspec \
    && apt-get update && apt-get install -y --no-install-recommends git ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && git config --system --add safe.directory '*'
# mcp<2: engine.py uses FastMCP, renamed in mcp 2.x. ruff: the gates check new Python lines; keep it
# at the version in skills/review-rules/rules/python.md.
RUN uv pip install --system --break-system-packages "mcp<2" pyyaml "ruff==0.17.1"
