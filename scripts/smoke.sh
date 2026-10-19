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

# A pre-populated user config dir: proves user files win and settings are merged.
SMOKE_CFG="$(mktemp -d)"
echo "KEEP" >"$SMOKE_CFG/AGENTS.md"
printf '%s\n' '{"defaultTools":["+codemode"],"theme":"user-theme","skills":["/user/skills"]}' >"$SMOKE_CFG/settings.json"
chmod 0777 "$SMOKE_CFG"                  # container runs as uid 1000, not root
chmod 0644 "$SMOKE_CFG/AGENTS.md"
chmod 0666 "$SMOKE_CFG/settings.json"    # so the entrypoint can merge into it
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
check "tini is PID 1"                       drun "$IMAGE" bash -lc 'cat /proc/1/comm | grep -qx tini'

section "system config layer (/etc/pi/agent)"
check "ships merged-by-default settings"    drun "$IMAGE" bash -lc 'test -s /etc/pi/agent/settings.json && grep -q /etc/pi/agent/skills /etc/pi/agent/settings.json'
check "ships operator-dev skill"            drun "$IMAGE" bash -lc 'test -s /etc/pi/agent/skills/operator-dev/SKILL.md'
check "ships gitcode-api skill"             drun "$IMAGE" bash -lc 'test -s /etc/pi/agent/skills/gitcode-api/SKILL.md'
check "ships the prompts directory"         drun "$IMAGE" bash -lc 'test -d /etc/pi/agent/prompts'
check "ships the gitcode extension"         drun "$IMAGE" bash -lc 'test -s /etc/pi/agent/extensions/gitcode/index.ts'

section "entrypoint / merged user config"
check "generates an SSH key"                drun "$IMAGE" bash -lc 'test -s ~/.ssh/id_ed25519 && test -s ~/.ssh/id_ed25519.pub'
check "writes ~/.ssh/config for gitcode"    drun "$IMAGE" bash -lc 'grep -q "Host gitcode.com" ~/.ssh/config'
check "installs AGENTS.md"                  drun "$IMAGE" bash -lc 'test -s "${PI_CODING_AGENT_DIR}/AGENTS.md"'
check "merges settings.json"                drun "$IMAGE" bash -lc 'grep -q /etc/pi/agent/skills "${PI_CODING_AGENT_DIR}/settings.json" && grep -q codemode "${PI_CODING_AGENT_DIR}/settings.json"'
check "merges mcp.json"                     drun "$IMAGE" bash -lc 'grep -q gitcode "${PI_CODING_AGENT_DIR}/mcp.json"'
check "sets git identity"                   drun "$IMAGE" bash -lc 'git config --global user.name && git config --global user.email'
check "user AGENTS.md wins"                 drun -v "$SMOKE_CFG:/home/agent/.pi/agent" "$IMAGE" bash -lc 'grep -qx KEEP "${PI_CODING_AGENT_DIR}/AGENTS.md"'
check "user settings merged, not clobbered" drun -v "$SMOKE_CFG:/home/agent/.pi/agent" "$IMAGE" bash -lc 'grep -q user-theme "${PI_CODING_AGENT_DIR}/settings.json" && grep -q /etc/pi/agent/skills "${PI_CODING_AGENT_DIR}/settings.json" && grep -q /user/skills "${PI_CODING_AGENT_DIR}/settings.json"'
check "fresh .ssh named volume is writable" drun -v "$SMOKE_VOL:/home/agent/.ssh" "$IMAGE" bash -lc 'test -s ~/.ssh/id_ed25519.pub'
check "/workspace is writable"              drun "$IMAGE" bash -lc 'touch /workspace/.smoke && rm -f /workspace/.smoke'

section "agent harness + resources"
check "pi -h exits 0"                       drun "$IMAGE" bash -lc 'pi --help >/dev/null'
check "pi mcp list sees the gitcode server" drun "$IMAGE" bash -lc 'timeout 90 pi mcp list 2>&1 | grep -qi gitcode'

SMOKE_RPC="$(drun "$IMAGE" bash -lc "printf '%s\n' '{\"type\":\"get_commands\"}' | timeout 90 pi --mode rpc 2>/dev/null" || true)"
for name in gitcode skill:operator-dev skill:gitcode-api; do
  if printf '%s' "$SMOKE_RPC" | grep -q "\"name\":\"$name\""; then
    ok "pi exposes $name"
  else
    bad "pi exposes $name"
    printf '       rpc bytes: %s\n' "${#SMOKE_RPC}"
  fi
done

printf '\n\033[1m== summary ==\033[0m\n  passed: %d\n  failed: %d\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
