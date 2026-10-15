#!/usr/bin/env bash
# =============================================================================
# hiascend-agent shell entrypoint
#
# Prepares, in order:
#   1. an SSH identity for gitcode.com   (generated on first run, printed)
#   2. the Pi config directory           (defaults injected if the mount is empty)
#   3. the git identity                  (from env, with sane defaults)
#   ...then execs the container CMD (default: bash; pass `pi` for the TUI).
#
# Set AGENT_SHELL_QUIET=1 to suppress the startup banner.
# =============================================================================
set -euo pipefail

AGENT_HOME="${HOME:-/home/agent}"
PI_DIR="${PI_CODING_AGENT_DIR:-$AGENT_HOME/.pi/agent}"
SSH_DIR="$AGENT_HOME/.ssh"
DEFAULTS="/opt/pi-defaults"
GITCODE_HOST="${GITCODE_SSH_HOST:-gitcode.com}"

log() { printf '\033[36m[agent-shell]\033[0m %s\n' "$*" >&2; }

# --- 1. SSH identity ---------------------------------------------------------
mkdir -p "$SSH_DIR" 2>/dev/null || true
chmod 700 "$SSH_DIR" 2>/dev/null || true

if [ ! -f "$SSH_DIR/id_ed25519" ]; then
  if ssh-keygen -t ed25519 -N '' -C "hiascend-agent@$(hostname)" \
       -f "$SSH_DIR/id_ed25519" >/dev/null 2>&1; then
    log "generated a new SSH key: $SSH_DIR/id_ed25519"
  else
    log "ERROR: cannot write $SSH_DIR (check the ownership of a mounted volume;"
    log "       the container runs as uid $(id -u) 'agent')"
  fi
fi
chmod 600 "$SSH_DIR/id_ed25519" 2>/dev/null || true
chmod 644 "$SSH_DIR/id_ed25519.pub" 2>/dev/null || true

if ! grep -qs "$GITCODE_HOST" "$SSH_DIR/known_hosts" 2>/dev/null; then
  ssh-keyscan -H "$GITCODE_HOST" >>"$SSH_DIR/known_hosts" 2>/dev/null || true
fi

if ! grep -qs "Host $GITCODE_HOST" "$SSH_DIR/config" 2>/dev/null; then
  cat >>"$SSH_DIR/config" <<CFG

Host $GITCODE_HOST
  HostName $GITCODE_HOST
  User git
  IdentityFile ~/.ssh/id_ed25519
  IdentitiesOnly yes
  StrictHostKeyChecking accept-new
  UserKnownHostsFile ~/.ssh/known_hosts
CFG
fi
chmod 600 "$SSH_DIR/config" 2>/dev/null || true

# --- 2. Pi config ------------------------------------------------------------
# Tolerant of a mounted directory the user cannot write: warn, never abort.
mkdir -p "$PI_DIR" 2>/dev/null || true
if [ -d "$DEFAULTS" ]; then
  for f in AGENTS.md mcp.json settings.json; do
    if [ -f "$DEFAULTS/$f" ] && [ ! -e "$PI_DIR/$f" ]; then
      cp "$DEFAULTS/$f" "$PI_DIR/$f" 2>/dev/null \
        || log "warning: cannot write $PI_DIR/$f (skipped)"
    fi
  done
  if [ -d "$DEFAULTS/skills" ]; then
    mkdir -p "$PI_DIR/skills" 2>/dev/null || true
    for d in "$DEFAULTS"/skills/*/; do
      [ -d "$d" ] || continue
      name="$(basename "$d")"
      if [ ! -e "$PI_DIR/skills/$name" ]; then
        cp -r "$d" "$PI_DIR/skills/$name" 2>/dev/null \
          || log "warning: cannot write $PI_DIR/skills/$name (skipped)"
      fi
    done
  fi
  if [ -d "$DEFAULTS/extensions" ]; then
    mkdir -p "$PI_DIR/extensions" 2>/dev/null || true
    for d in "$DEFAULTS"/extensions/*/; do
      [ -d "$d" ] || continue
      name="$(basename "$d")"
      if [ ! -e "$PI_DIR/extensions/$name" ]; then
        cp -r "$d" "$PI_DIR/extensions/$name" 2>/dev/null \
          || log "warning: cannot write $PI_DIR/extensions/$name (skipped)"
      fi
    done
  fi
fi

# --- 3. git identity ---------------------------------------------------------
git config --global user.name  "${GIT_AUTHOR_NAME:-${GIT_USER_NAME:-hiascend-agent}}"
git config --global user.email "${GIT_AUTHOR_EMAIL:-${GIT_USER_EMAIL:-hiascend-agent@localhost}}"
git config --global --add safe.directory '*'
git config --global init.defaultBranch master

# HTTPS fallback: let git read the token straight from the environment, so no
# secret is ever written to disk. SSH remains the primary transport.
if [ -n "${GITCODE_ACCESS_TOKEN:-}" ] \
   && ! git config --global --get-regexp '^credential\..*\.helper$' >/dev/null 2>&1; then
  git config --global "credential.https://${GITCODE_HOST}.helper" \
    '!f() { echo username="${GITCODE_USERNAME:-oauth2}"; echo "password=${GITCODE_ACCESS_TOKEN}"; }; f'
fi

# --- 4. banner ---------------------------------------------------------------
mkdir -p /workspace 2>/dev/null || true

if [ "${AGENT_SHELL_QUIET:-0}" != "1" ]; then
  log "pi $(pi --version 2>/dev/null || echo '?') | git $(git --version | awk '{print $3}') | $(gitcode-api --version 2>/dev/null || echo 'gitcode-api ?')"
  log "config dir : $PI_DIR"
  log "workspace  : /workspace"

  ssh_out="$(ssh -o BatchMode=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=accept-new \
                  -T "git@$GITCODE_HOST" 2>&1 || true)"
  if printf '%s' "$ssh_out" | grep -qi 'permission denied'; then
    log "GitCode SSH: not authenticated yet."
    log "add this public key at https://$GITCODE_HOST/setting/key-ssh :"
    sed 's/^/    /' "$SSH_DIR/id_ed25519.pub" >&2
  elif printf '%s' "$ssh_out" | grep -qi 'denied\|failure'; then
    log "GitCode SSH: check failed ($(printf '%s' "$ssh_out" | head -n1))"
  else
    log "GitCode SSH: ok ($(printf '%s' "$ssh_out" | head -n1))"
  fi
fi

exec "$@"
