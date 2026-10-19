#!/usr/bin/env bash
# =============================================================================
# Install the release package in a clean, offline container and verify it.
#
#   packaging/test-in-container.sh [tarball]
#   IMAGE=openeuler/openeuler:24.03-lts packaging/test-in-container.sh
#
# The container has no network (--network none), which is the intended target
# environment. git/ssh are optional and only produce doctor warnings.
# =============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARBALL="${1:-$(ls -t "$ROOT"/dist/hiascend-agent-*.tar.gz 2>/dev/null | head -n1 || true)}"
IMAGE="${IMAGE:-openeuler/openeuler:24.03-lts}"

[ -n "$TARBALL" ] && [ -f "$TARBALL" ] || {
	echo "no release tarball found; run packaging/build-release.sh first" >&2
	exit 1
}

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
tar xzf "$TARBALL" -C "$WORK"
PKG="$WORK/$(basename "${TARBALL%.tar.gz}")"
[ -d "$PKG" ] || { echo "unexpected tarball layout" >&2; exit 1; }

echo "== testing $(basename "$TARBALL") in $IMAGE (offline) =="

docker run --rm --network none -v "$PKG:/pkg:ro" "$IMAGE" bash -lc '
set -e
echo "-- pre-seed a user config (must be preserved) --"
mkdir -p /root/.pi/agent
printf "%s\n" "{\"theme\":\"keep-me\",\"skills\":[\"/root/my-skills\"]}" > /root/.pi/agent/settings.json

echo "-- install --"
cd /pkg
./install.sh --prefix /opt/hiascend-agent --no-ssh-keygen --no-git-config --no-doctor

echo "-- idempotent re-install --"
./install.sh --prefix /opt/hiascend-agent --no-ssh-keygen --no-git-config --no-doctor

echo "-- verify --"
grep -q keep-me /root/.pi/agent/settings.json
grep -q /root/my-skills /root/.pi/agent/settings.json
grep -q /opt/hiascend-agent/current/config/skills /root/.pi/agent/settings.json
test -x /opt/hiascend-agent/current/bin/pi
test -x /usr/local/bin/hiascend-agent
hiascend-agent pi --version

echo "-- doctor --"
hiascend-agent doctor

echo "-- version --"
hiascend-agent version

echo "-- uninstall --"
hiascend-agent uninstall
test ! -e /opt/hiascend-agent/0.1.0
test ! -e /usr/local/bin/hiascend-agent
echo "ALL CHECKS PASSED"
'
