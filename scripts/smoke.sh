#!/usr/bin/env bash
# =============================================================================
# Smoke test — no credentials required.
#
# Builds the image and asserts that the Phase-1 toolchain and the entrypoint's
# first-run behaviour are correct. Run this from the VM guest:
#
#     bash /work/scripts/smoke.sh
#
# Override the tag with IMAGE=... and skip the build with SKIP_BUILD=1.
# =============================================================================
set -uo pipefail
cd "$(dirname "$0")/.."

IMAGE="${IMAGE:-hiascend-agent-shell:latest}"
PASS=0
FAIL=0

ok()      { printf '  \033[32mPASS\033[0m %s\n' "$*"; PASS=$((PASS + 1)); }
bad()     { printf '  \033[31mFAIL\033[0m %s\n' "$*"; FAIL=$((FAIL + 1)); }
section() { printf '\n\033[1m== %s ==\033[0m\n' "$*"; }

drun() { docker run --rm -e AGENT_SHELL_QUIET=1 "$@"; }

# check <description> <command...>
check() {
  local desc="$1"; shift
  if out="$("$@" 2>&1)"; then
    ok "$desc"
  else
    bad "$desc"
    printf '       %s\n' "$(printf '%s' "$out" | tail -n3)"
  fi
}

if [ "${SKIP_BUILD:-0}" != "1" ]; then
  section "build"
  if docker build -t "$IMAGE" .; then ok "docker build"; else bad "docker build"; exit 1; fi
fi

# A pre-populated config dir, to prove the entrypoint never clobbers a mount.
SMOKE_CFG="$(mktemp -d)"
echo "KEEP" >"$SMOKE_CFG/AGENTS.md"
chmod 0777 "$SMOKE_CFG"          # container runs as uid 1000, not root
chmod 0644 "$SMOKE_CFG/AGENTS.md"
# A fresh named volume, to prove docker's volume-init keeps agent ownership.
SMOKE_VOL="agent-shell-smoke-$$"
docker volume create "$SMOKE_VOL" >/dev/null
trap 'rm -rf "$SMOKE_CFG"; docker volume rm -f "$SMOKE_VOL" >/dev/null 2>&1 || true' EXIT

section "toolchain"
check "runs as non-root 'agent' (uid 1000)" drun "$IMAGE" bash -lc 'test "$(id -un)" = agent && test "$(id -u)" = 1000'
check "pi is installed"                     drun "$IMAGE" bash -lc 'pi --version'
check "git is installed"                    drun "$IMAGE" bash -lc 'git --version'
check "gitcode-api CLI works"               drun "$IMAGE" bash -lc 'gitcode-api --version && gitcode-api --help >/dev/null'
check "uv is installed"                     drun "$IMAGE" bash -lc 'uv --version'
check "python3 is installed"                drun "$IMAGE" bash -lc 'python3 --version'
check "ssh-keygen is installed"             drun "$IMAGE" bash -lc 'command -v ssh-keygen >/dev/null'
check "tini is PID 1"                        drun "$IMAGE" bash -lc 'cat /proc/1/comm | grep -qx tini'

section "entrypoint / first-run config"
check "generates an SSH key"                drun "$IMAGE" bash -lc 'test -s ~/.ssh/id_ed25519 && test -s ~/.ssh/id_ed25519.pub'
check "writes ~/.ssh/config for gitcode"    drun "$IMAGE" bash -lc 'grep -q "Host gitcode.com" ~/.ssh/config'
check "injects Pi AGENTS.md"                drun "$IMAGE" bash -lc 'test -s "${PI_CODING_AGENT_DIR}/AGENTS.md"'
check "injects Pi mcp.json"                 drun "$IMAGE" bash -lc 'test -s "${PI_CODING_AGENT_DIR}/mcp.json"'
check "injects settings.json"               drun "$IMAGE" bash -lc 'test -s "${PI_CODING_AGENT_DIR}/settings.json"'
check "injects gitcode-api skill"           drun "$IMAGE" bash -lc 'test -s "${PI_CODING_AGENT_DIR}/skills/gitcode-api/SKILL.md"'
check "sets git identity"                   drun "$IMAGE" bash -lc 'git config --global user.name && git config --global user.email'
check "keeps a mounted config intact"       drun -v "$SMOKE_CFG:/home/agent/.pi/agent" "$IMAGE" bash -lc 'grep -qx KEEP "${PI_CODING_AGENT_DIR}/AGENTS.md"'
check "fresh .ssh named volume is writable" drun -v "$SMOKE_VOL:/home/agent/.ssh" "$IMAGE" bash -lc 'test -s ~/.ssh/id_ed25519.pub'
check "/workspace is writable"              drun "$IMAGE" bash -lc 'touch /workspace/.smoke && rm -f /workspace/.smoke'

section "agent harness can start"
check "pi -h exits 0"                       drun "$IMAGE" bash -lc 'pi --help >/dev/null'
check "pi mcp list sees the gitcode server" drun "$IMAGE" bash -lc 'timeout 90 pi mcp list 2>&1 | grep -qi gitcode'

section "gitcode extension"
check "injects the gitcode extension"       drun "$IMAGE" bash -lc 'test -s "${PI_CODING_AGENT_DIR}/extensions/gitcode/index.ts"'
SMOKE_RPC="$(drun "$IMAGE" bash -lc "printf '%s\n' '{\"type\":\"get_commands\"}' | timeout 90 pi --mode rpc 2>/dev/null" || true)"
if printf '%s' "$SMOKE_RPC" | grep -q '"name":"gitcode"'; then
  ok "pi registers the gitcode extension (/gitcode present)"
else
  bad "pi registers the gitcode extension (/gitcode present)"
  printf '       rpc bytes: %s\n' "${#SMOKE_RPC}"
fi

printf '\n\033[1m== summary ==\033[0m\n  passed: %d\n  failed: %d\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
