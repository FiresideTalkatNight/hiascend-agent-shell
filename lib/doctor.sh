#!/usr/bin/env bash
# =============================================================================
# hiascend-agent doctor — verify the installed environment and bundled resources.
# Called by `hiascend-agent doctor`; inherits PATH/PI_CODING_AGENT_DIR.
# =============================================================================
set -uo pipefail

SELF="$(readlink -f "${BASH_SOURCE[0]}")"
ROOT="$(cd "$(dirname "$SELF")/.." && pwd)"
PREFIX="$(cd "$ROOT/.." && pwd)"
EXPECTED_PI="$(cat "$ROOT/PI_VERSION" 2>/dev/null || echo '')"

export PATH="$ROOT/bin:$ROOT/venv/bin:$PATH"
export GITCODE_API_BIN="${GITCODE_API_BIN:-$ROOT/venv/bin/gitcode-api}"
export PI_CODING_AGENT_DIR="${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}"

PASS=0
FAIL=0
WARN=0

ok()   { printf '  \033[32mPASS\033[0m %s\n' "$*"; PASS=$((PASS + 1)); }
bad()  { printf '  \033[31mFAIL\033[0m %s\n' "$*"; FAIL=$((FAIL + 1)); }
warn() { printf '  \033[33mWARN\033[0m %s\n' "$*"; WARN=$((WARN + 1)); }
section() { printf '\n\033[1m== %s ==\033[0m\n' "$*"; }

have() { command -v "$1" >/dev/null 2>&1; }

section "binaries"
if have pi; then
	version="$(pi --version 2>/dev/null | head -n1)"
	if [ -z "$EXPECTED_PI" ] || [ "$version" = "$EXPECTED_PI" ]; then
		ok "pi $version"
	else
		bad "pi version $version (expected $EXPECTED_PI)"
	fi
else
	bad "pi not found on PATH"
fi
have fd && ok "fd $(fd --version 2>/dev/null | head -n1)" || bad "fd not found"
have rg && ok "rg $(rg --version 2>/dev/null | head -n1)" || bad "rg not found"
have git && ok "git $(git --version 2>/dev/null | sed 's/^git version //')" || warn "git not found (SCM steps need it)"
have ssh && ok "ssh available" || warn "ssh not found (GitCode push/pull needs it)"
have ssh-keygen && ok "ssh-keygen available" || warn "ssh-keygen not found"

section "python + gitcode-api"
if [ -x "$ROOT/venv/bin/python" ]; then
	ok "venv python $("$ROOT/venv/bin/python" --version 2>&1)"
else
	bad "venv python missing at $ROOT/venv/bin/python"
fi
if have gitcode-api; then
	ok "gitcode-api $(gitcode-api --version 2>/dev/null | head -n1)"
else
	bad "gitcode-api not found"
fi

section "Pi configuration"
if [ -r "$PI_CODING_AGENT_DIR/settings.json" ]; then
	if grep -q "$PREFIX/current/config" "$PI_CODING_AGENT_DIR/settings.json"; then
		ok "settings.json references the package config layer"
	else
		bad "settings.json does not reference $PREFIX/current/config"
	fi
else
	bad "settings.json missing in $PI_CODING_AGENT_DIR"
fi
if [ -r "$PI_CODING_AGENT_DIR/mcp.json" ] && grep -q gitcode "$PI_CODING_AGENT_DIR/mcp.json"; then
	ok "mcp.json registers the gitcode server"
else
	warn "mcp.json does not register the gitcode server"
fi

section "Pi resource discovery"
RPC="$(printf '%s\n' '{"type":"get_commands"}' | timeout 90 pi --mode rpc 2>/dev/null || true)"
check_resource() {
	local name="$1"
	if printf '%s' "$RPC" | grep -q "\"name\":\"$name\""; then
		ok "$name"
	else
		bad "$name not discovered"
	fi
}
check_resource "gitcode"
check_resource "skill:operator-dev"
check_resource "skill:gitcode-api"
for template in "$ROOT"/config/prompts/*.md; do
	[ -f "$template" ] || continue
	check_resource "$(basename "$template" .md)"
done

section "GitCode credentials"
if [ -n "${GITCODE_ACCESS_TOKEN:-}" ]; then
	ok "GITCODE_ACCESS_TOKEN is set"
else
	warn "GITCODE_ACCESS_TOKEN is not set (fork/PR need it)"
fi
if [ -s "$HOME/.ssh/id_ed25519.pub" ]; then
	ok "SSH public key present: $HOME/.ssh/id_ed25519.pub"
else
	warn "no SSH key at $HOME/.ssh/id_ed25519.pub"
fi

section "Ascend / CANN (informational)"
if have npu-smi; then ok "npu-smi available"; else warn "npu-smi not found (tests need the NPU environment)"; fi
if [ -n "${ASCEND_HOME:-}" ]; then
	ok "ASCEND_HOME=$ASCEND_HOME"
elif [ -d /usr/local/Ascend/ascend-toolkit ] || [ -d /usr/local/Ascend/latest ]; then
	ok "CANN toolkit found under /usr/local/Ascend (ASCEND_HOME not set)"
else
	warn "ASCEND_HOME is not set and no CANN toolkit found under /usr/local/Ascend"
fi

printf '\n\033[1m== summary ==\033[0m\n  passed: %d\n  warnings: %d\n  failed: %d\n' "$PASS" "$WARN" "$FAIL"
[ "$FAIL" -eq 0 ]
