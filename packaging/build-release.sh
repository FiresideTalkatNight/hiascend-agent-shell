#!/usr/bin/env bash
# =============================================================================
# Build the relocatable release tarball.
#
# Source inputs (repo): install.sh, uninstall.sh, bin/, lib/, config/
# Downloaded inputs (pinned in packaging/versions.env):
#   - Pi standalone binary (linux-x64)
#   - fd and ripgrep (musl static)
#   - gitcode-api[mcp] wheels for CPython 3.11 / manylinux x86_64
#
# Usage:
#   packaging/build-release.sh                 # direct GitHub downloads
#   GHPROXY=https://ghproxy.com/ packaging/build-release.sh
#   PYTHON=python3.11 packaging/build-release.sh
#
# Output:
#   dist/hiascend-agent-<pkgver>-linux-x86_64.tar.gz
#   dist/hiascend-agent-<pkgver>-linux-x86_64.tar.gz.sha256
# =============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
# shellcheck source=packaging/versions.env
. packaging/versions.env

BUILD="${BUILD:-$ROOT/build}"
DIST="${DIST:-$ROOT/dist}"
CACHE="$BUILD/cache"
STAGE="$BUILD/hiascend-agent-${PKG_VERSION}-linux-${TARGET_ARCH}"
GHPROXY="${GHPROXY:-}"
PYTHON="${PYTHON:-python3.11}"

die() { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }
log() { printf '\033[36m[release]\033[0m %s\n' "$*"; }

fetch() {
	local url="$1" out="$2"
	[ -s "$out" ] && { log "cached $(basename "$out")"; return 0; }
	log "download ${GHPROXY}${url}"
	curl -fL --retry 3 --retry-delay 2 --connect-timeout 20 --max-time 600 \
		-o "$out.tmp" "${GHPROXY}${url}"
	mv "$out.tmp" "$out"
}

verify() {
	local file="$1" want="$2"
	local got
	got="$(sha256sum "$file" | awk '{print $1}')"
	[ "$got" = "$want" ] || die "checksum mismatch for $(basename "$file"): $got != $want"
	log "verified $(basename "$file")"
}

download_wheels() {
	local dest="$1"
	if command -v "$PYTHON" >/dev/null 2>&1 && "$PYTHON" -m pip --version >/dev/null 2>&1; then
		"$PYTHON" -m pip download --disable-pip-version-check --dest "$dest" \
			--only-binary=:all: \
			--python-version 3.11 --implementation cp --abi cp311 \
			--platform manylinux2014_x86_64 \
			--platform manylinux_2_28_x86_64 \
			"gitcode-api[mcp]==${GITCODE_API_VERSION}"
	elif command -v docker >/dev/null 2>&1; then
		log "no $PYTHON; downloading wheels via python:3.11-slim"
		docker run --rm -v "$dest:/wheels" python:3.11-slim \
			pip download --disable-pip-version-check --dest /wheels \
			--only-binary=:all: \
			--python-version 3.11 --implementation cp --abi cp311 \
			--platform manylinux2014_x86_64 \
			--platform manylinux_2_28_x86_64 \
			"gitcode-api[mcp]==${GITCODE_API_VERSION}"
	else
		die "need $PYTHON with pip (or docker) to download wheels"
	fi
}

log "preparing build directories"
mkdir -p "$CACHE" "$DIST"
rm -rf "$STAGE"
mkdir -p "$STAGE"/{bin,lib,config,vendor/wheels,vendor/bin}

log "fetching pinned binaries"
fetch "$PI_URL" "$CACHE/$PI_ASSET"; verify "$CACHE/$PI_ASSET" "$PI_SHA256"
fetch "$FD_URL" "$CACHE/$FD_ASSET"; verify "$CACHE/$FD_ASSET" "$FD_SHA256"
fetch "$RG_URL" "$CACHE/$RG_ASSET"; verify "$CACHE/$RG_ASSET" "$RG_SHA256"

log "extracting binaries"
rm -rf "$BUILD/pi" "$BUILD"/fd-* "$BUILD"/ripgrep-*
tar xzf "$CACHE/$PI_ASSET" --no-same-owner -C "$BUILD"
tar xzf "$CACHE/$FD_ASSET" --no-same-owner -C "$BUILD"
tar xzf "$CACHE/$RG_ASSET" --no-same-owner -C "$BUILD"
cp -a --no-preserve=ownership "$BUILD/pi" "$STAGE/vendor/pi"
cp "$BUILD"/fd-*/fd "$STAGE/vendor/bin/fd"
cp "$BUILD"/ripgrep-*/rg "$STAGE/vendor/bin/rg"
chmod 0755 "$STAGE/vendor/pi/pi" "$STAGE/vendor/bin/fd" "$STAGE/vendor/bin/rg"

log "downloading gitcode-api[mcp] ${GITCODE_API_VERSION} wheels (cp311)"
WHEEL_CACHE="$BUILD/wheels"
mkdir -p "$WHEEL_CACHE"
if ls "$WHEEL_CACHE"/*.whl >/dev/null 2>&1; then
	log "using cached wheels"
	cp -a "$WHEEL_CACHE"/. "$STAGE/vendor/wheels/"
else
	download_wheels "$STAGE/vendor/wheels"
	cp -a "$STAGE/vendor/wheels"/. "$WHEEL_CACHE/"
fi

log "assembling package"
cp install.sh uninstall.sh "$STAGE/"
cp -a --no-preserve=ownership bin lib config "$STAGE/"
find "$STAGE" -name __pycache__ -type d -prune -exec rm -rf {} +
cp packaging/versions.env "$STAGE/versions.env"
chmod 0755 "$STAGE/install.sh" "$STAGE/uninstall.sh" "$STAGE/bin/hiascend-agent"
printf '%s\n' "$PKG_VERSION" >"$STAGE/VERSION"
printf '%s\n' "$PI_VERSION" >"$STAGE/PI_VERSION"

log "writing checksums"
(
	cd "$STAGE"
	find . -type f ! -name SHA256SUMS -print0 | sort -z | xargs -0 sha256sum >SHA256SUMS
)

TARBALL="$DIST/hiascend-agent-${PKG_VERSION}-linux-${TARGET_ARCH}.tar.gz"
log "creating $TARBALL"
tar czf "$TARBALL" -C "$BUILD" "$(basename "$STAGE")"
(
	cd "$DIST"
	sha256sum "$(basename "$TARBALL")" >"$(basename "$TARBALL").sha256"
)
log "done: $TARBALL"
ls -lh "$TARBALL"
