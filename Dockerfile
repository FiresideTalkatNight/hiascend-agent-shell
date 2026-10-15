# syntax=docker/dockerfile:1
# =============================================================================
# hiascend-agent shell  ·  Phase-1
#
# An interactive agent shell that can operate GitCode autonomously
# (fork -> develop -> push -> pull request).
#
#   * Pi (pi-agent) as the agent harness   -> https://pi.dev
#   * git / openssh-client for the SCM path
#   * gitcode-api (Python SDK + CLI + MCP server) for the GitCode REST path
#   * uv, so the agent can pull extra Python tooling on demand
#
# Base image follows Pi's own containerization guidance
# (packages/coding-agent/docs/containerization.md): node:24-bookworm-slim.
# =============================================================================
FROM node:24-bookworm-slim

ARG PI_VERSION=1.1.0
ARG GITCODE_API_VERSION=1.3.4

LABEL org.opencontainers.image.title="hiascend-agent-shell" \
      org.opencontainers.image.description="Interactive Pi agent shell with GitCode tooling for automated operator-development tasks" \
      org.opencontainers.image.version="phase1" \
      org.opencontainers.image.licenses="MIT"

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    PATH="/opt/venv/bin:${PATH}" \
    PI_CODING_AGENT_DIR=/home/agent/.pi/agent

# --- OS packages -------------------------------------------------------------
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      bash \
      ca-certificates \
      git \
      git-lfs \
      openssh-client \
      curl \
      wget \
      ripgrep \
      jq \
      less \
      procps \
      python3 \
      python3-venv \
      unzip \
      tini \
 && rm -rf /var/lib/apt/lists/*

# best-effort git-lfs setup (does not affect package installation above)
RUN git lfs install --system >/dev/null 2>&1 || true

# --- Python tooling: gitcode-api (+ MCP extra) and uv, in a dedicated venv ---
RUN python3 -m venv /opt/venv \
 && /opt/venv/bin/pip install --no-cache-dir --upgrade pip \
 && /opt/venv/bin/pip install --no-cache-dir \
      "uv" \
      "gitcode-api[mcp]==${GITCODE_API_VERSION}"

# --- Pi (agent harness) ------------------------------------------------------
RUN npm install -g --ignore-scripts "@earendil-works/pi-coding-agent@${PI_VERSION}" \
 && npm cache clean --force

# --- Non-root user ------------------------------------------------------------
# Reuse the base image's uid/gid 1000 (the "node" user) so mounted host
# directories owned by the developer's uid keep working. Rename it to "agent".
RUN groupmod -n agent node \
 && usermod -l agent -d /home/agent -m node \
 && mkdir -p /workspace \
 && install -d -m 700 -o agent -g agent /home/agent/.ssh \
 && chown -R agent:agent /home/agent /workspace

# --- Pi default config template ----------------------------------------------
# Injected into an *empty* ~/.pi/agent at first run (see entrypoint.sh); a
# mounted config directory always wins.
COPY pi-defaults/ /opt/pi-defaults/
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# A login shell (/etc/profile) resets PATH and would drop the venv; restore it.
RUN printf 'export PATH="/opt/venv/bin:$PATH"\n' > /etc/profile.d/00-agent-venv.sh \
 && chmod 0644 /etc/profile.d/00-agent-venv.sh

USER agent
WORKDIR /workspace

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
CMD ["bash"]
