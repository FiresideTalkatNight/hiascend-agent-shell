#!/usr/bin/env bash
# =============================================================================
# Convenience launcher for the agent shell.
#
#   ./run.sh                 # interactive bash inside the container
#   ./run.sh pi              # start the Pi TUI directly
#   ./run.sh pi -p "..."     # one-shot agent prompt
#
# Mounts (create the host dirs first, or let them be created):
#   ./e2e/pi-agent  -> /home/agent/.pi/agent   (provider auth, settings, MCP)
#   ./workspace     -> /workspace              (your project checkout)
#   named volume    -> /home/agent/.ssh        (SSH key, generated on first run)
#
# Env variables are forwarded if set: GITCODE_ACCESS_TOKEN, DEEPSEEK_API_KEY,
# OPENAI_API_KEY, ANTHROPIC_API_KEY, GIT_AUTHOR_NAME, GIT_AUTHOR_EMAIL.
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")"

IMAGE="${IMAGE:-hiascend-agent-shell:latest}"
CFG_DIR="${CFG_DIR:-$PWD/e2e/pi-agent}"
WORKSPACE_DIR="${WORKSPACE_DIR:-$PWD/workspace}"
SSH_VOLUME="${SSH_VOLUME:-agent-shell-ssh}"

mkdir -p "$CFG_DIR" "$WORKSPACE_DIR"
chown -R 1000:1000 "$CFG_DIR" "$WORKSPACE_DIR" 2>/dev/null || true
docker volume inspect "$SSH_VOLUME" >/dev/null 2>&1 || docker volume create "$SSH_VOLUME" >/dev/null

env_args=()
for v in GITCODE_ACCESS_TOKEN DEEPSEEK_API_KEY OPENAI_API_KEY ANTHROPIC_API_KEY \
         GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL PI_CODING_AGENT_DIR; do
  if [ -n "${!v:-}" ]; then env_args+=(-e "$v"); fi
done

exec docker run --rm -it \
  "${env_args[@]}" \
  -v "$CFG_DIR:/home/agent/.pi/agent" \
  -v "$SSH_VOLUME:/home/agent/.ssh" \
  -v "$WORKSPACE_DIR:/workspace" \
  "$IMAGE" "$@"
