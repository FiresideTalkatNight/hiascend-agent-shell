#!/usr/bin/env bash
# =============================================================================
# hiascend-agent shell entrypoint
#
# Prepares, in order:
#   1. an SSH identity for gitcode.com   (generated on first run, printed)
#   2. the Pi configuration              (/etc/pi/agent merged into ~/.pi/agent)
#   3. the git identity                  (from env, with sane defaults)
#   ...then execs the container CMD (default: bash; pass `pi` for the TUI).
#
# Set AGENT_SHELL_QUIET=1 to suppress the startup banner.
# =============================================================================
set -euo pipefail

AGENT_HOME="${HOME:-/home/agent}"
PI_DIR="${PI_CODING_AGENT_DIR:-$AGENT_HOME/.pi/agent}"
SSH_DIR="$AGENT_HOME/.ssh"
SYSTEM_DIR="/etc/pi/agent"
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

# --- 2. Pi configuration: system layer + user layer (merged) -----------------
# System defaults live at /etc/pi/agent (baked into the image). The user's agent
# directory ($PI_DIR) stays writable and is commonly a mount. We merge:
#   settings.json : recursive merge, user wins; resource arrays are unioned
#                   (user first, so a user resource wins name collisions)
#   mcp.json      : mcpServers union, user wins per server name
#   AGENTS.md     : user file wins; the system one is only installed when absent
# Skills/prompts/extensions are referenced by absolute path in settings.json,
# so they always reflect the image and are never copied into user state.
mkdir -p "$PI_DIR" 2>/dev/null || true

merge_json() {
  # merge_json <system-file> <user-file> <jq-filter>
  local sys="$1" usr="$2" filter="$3" merged
  [ -f "$sys" ] || return 0
  if [ ! -f "$usr" ]; then
    cp "$sys" "$usr" 2>/dev/null || log "warning: cannot write $usr (skipped)"
    return 0
  fi
  if ! merged="$(jq -s "$filter" "$sys" "$usr" 2>/dev/null)"; then
    log "warning: cannot merge $usr (invalid JSON?); keeping the user file"
    return 0
  fi
  if printf '%s\n' "$merged" >"$usr.tmp" 2>/dev/null && mv "$usr.tmp" "$usr" 2>/dev/null; then
    :
  else
    rm -f "$usr.tmp" 2>/dev/null || true
    log "warning: cannot write $usr (read-only mount?); merge skipped"
  fi
}

merge_json "$SYSTEM_DIR/settings.json" "$PI_DIR/settings.json" '
  def uq: reduce .[] as $x ([]; if any(.[]; . == $x) then . else . + [$x] end);
  .[0] as $sys | .[1] as $usr |
  ($sys * $usr)
  | .skills     = ((($usr.skills     // []) + ($sys.skills     // [])) | uq)
  | .prompts    = ((($usr.prompts    // []) + ($sys.prompts    // [])) | uq)
  | .extensions = ((($usr.extensions // []) + ($sys.extensions // [])) | uq)
  | .themes     = ((($usr.themes     // []) + ($sys.themes     // [])) | uq)
  | .packages   = ((($usr.packages   // []) + ($sys.packages   // [])) | uq)
'

merge_json "$SYSTEM_DIR/mcp.json" "$PI_DIR/mcp.json" '
  .[0] as $sys | .[1] as $usr |
  { mcpServers: (($sys.mcpServers // {}) + ($usr.mcpServers // {})) }
'

if [ -f "$SYSTEM_DIR/AGENTS.md" ] && [ ! -e "$PI_DIR/AGENTS.md" ]; then
  cp "$SYSTEM_DIR/AGENTS.md" "$PI_DIR/AGENTS.md" 2>/dev/null \
    || log "warning: cannot write $PI_DIR/AGENTS.md (skipped)"
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
