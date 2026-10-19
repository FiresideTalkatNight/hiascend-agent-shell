#!/usr/bin/env bash
# =============================================================================
# hiascend-agent installer
#
# Installs the bundled agent shell (Pi + fd + ripgrep + gitcode-api + skills)
# into a versioned prefix and merges its Pi configuration into the user's
# agent directory. Designed for openEuler x86_64, offline use, running as root.
#
#   ./install.sh
#   ./install.sh --prefix /opt/hiascend-agent --bin-dir /usr/local/bin
#   ./install.sh --pi-dir /root/.pi/agent
#   ./install.sh --fetch --ghproxy https://ghproxy.com/   # only if vendor/ is absent
#   ./install.sh --uninstall [--purge-config]
# =============================================================================
set -euo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Pinned versions/URLs (present in the release package; also used by --fetch)
if [ -f "$SELF_DIR/versions.env" ]; then
	# shellcheck source=/dev/null
	. "$SELF_DIR/versions.env"
fi
PKG_VERSION="$(cat "$SELF_DIR/VERSION" 2>/dev/null || echo "${PKG_VERSION:-unknown}")"
PI_VERSION="$(cat "$SELF_DIR/PI_VERSION" 2>/dev/null || echo "${PI_VERSION:-unknown}")"

PREFIX="/opt/hiascend-agent"
BIN_DIR="/usr/local/bin"
PI_DIR="${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}"
GHPROXY=""
FETCH=0
SKIP_VERIFY=0
NO_SSH_KEYGEN=0
NO_GIT_CONFIG=0
NO_DOCTOR=0
UNINSTALL=0
PURGE_CONFIG=0

WORK=""
cleanup() {
	if [ -n "$WORK" ]; then rm -rf "$WORK"; fi
	return 0
}
trap cleanup EXIT

die() { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }
log() { printf '\033[36m[install]\033[0m %s\n' "$*"; }
warn() { printf '\033[33mwarning:\033[0m %s\n' "$*" >&2; }

usage() {
	cat <<EOF
hiascend-agent installer (package ${PKG_VERSION}, Pi ${PI_VERSION})

Usage: ./install.sh [options]

Options:
  --prefix DIR        install root (default: /opt/hiascend-agent)
  --bin-dir DIR       where to put the launcher (default: /usr/local/bin)
  --pi-dir DIR        user Pi agent directory (default: \$HOME/.pi/agent)
  --ghproxy URL       GitHub proxy prefix, e.g. https://ghproxy.com/
  --fetch             download missing pi/fd/rg assets (needs network/proxy)
  --skip-verify       skip SHA256SUMS verification of the package
  --no-ssh-keygen     do not create an SSH key
  --no-git-config     do not set git user.name/user.email
  --no-doctor         skip the post-install doctor
  --uninstall         remove the installation
  --purge-config      with --uninstall: remove package entries from Pi config
  -h, --help          show this help
EOF
}

while [ $# -gt 0 ]; do
	case "$1" in
		--prefix) PREFIX="${2:?}"; shift 2 ;;
		--bin-dir) BIN_DIR="${2:?}"; shift 2 ;;
		--pi-dir) PI_DIR="${2:?}"; shift 2 ;;
		--ghproxy) GHPROXY="${2:?}"; shift 2 ;;
		--fetch) FETCH=1; shift ;;
		--skip-verify) SKIP_VERIFY=1; shift ;;
		--no-ssh-keygen) NO_SSH_KEYGEN=1; shift ;;
		--no-git-config) NO_GIT_CONFIG=1; shift ;;
		--no-doctor) NO_DOCTOR=1; shift ;;
		--uninstall) UNINSTALL=1; shift ;;
		--purge-config) PURGE_CONFIG=1; shift ;;
		-h|--help) usage; exit 0 ;;
		*) die "unknown option: $1 (see --help)" ;;
	esac
done

if [ "$UNINSTALL" = 1 ]; then
	args=(--prefix "$PREFIX" --bin-dir "$BIN_DIR" --pi-dir "$PI_DIR")
	[ "$PURGE_CONFIG" = 1 ] && args+=(--purge-config)
	exec "$SELF_DIR/uninstall.sh" "${args[@]}"
fi

# --- checks ------------------------------------------------------------------
[ "$(id -u)" = 0 ] || warn "not running as root; installation may fail for $PREFIX/$BIN_DIR"
command -v tar >/dev/null || die "tar is required"
command -v sha256sum >/dev/null || die "sha256sum is required"
if [ "$FETCH" = 1 ]; then
	command -v curl >/dev/null || die "curl is required for --fetch"
fi

PYTHON=""
for candidate in python3.11 python3; do
	if command -v "$candidate" >/dev/null 2>&1; then
		if "$candidate" -c 'import sys; raise SystemExit(0 if sys.version_info >= (3,9) else 1)'; then
			PYTHON="$candidate"
			break
		fi
	fi
done
[ -n "$PYTHON" ] || die "python3.11 (or python3 >= 3.9) is required for gitcode-api"
log "using $PYTHON ($($PYTHON --version 2>&1))"

# --- package integrity -------------------------------------------------------
if [ "$SKIP_VERIFY" = 0 ] && [ -f "$SELF_DIR/SHA256SUMS" ] && [ -d "$SELF_DIR/vendor" ]; then
	( cd "$SELF_DIR" && sha256sum -c SHA256SUMS --quiet ) \
		|| die "package integrity check failed (use --skip-verify to bypass)"
	log "package checksums verified"
fi

# --- vendor assets -----------------------------------------------------------
VENDOR_PI="$SELF_DIR/vendor/pi"
VENDOR_FD="$SELF_DIR/vendor/bin/fd"
VENDOR_RG="$SELF_DIR/vendor/bin/rg"
WHEELS_DIR="$SELF_DIR/vendor/wheels"

if [ ! -d "$WHEELS_DIR" ] || ! ls "$WHEELS_DIR"/*.whl >/dev/null 2>&1; then
	die "bundled Python wheels are missing ($WHEELS_DIR).
Build the release package with packaging/build-release.sh; wheels cannot be
downloaded offline through ghproxy."
fi

if [ ! -x "$VENDOR_PI/pi" ] || [ ! -x "$VENDOR_FD" ] || [ ! -x "$VENDOR_RG" ]; then
	[ "$FETCH" = 1 ] || die "vendor binaries missing; re-download the release package or use --fetch --ghproxy URL"
	[ -n "${PI_URL:-}" ] || die "versions.env missing; cannot fetch assets"
	WORK="$(mktemp -d)"
	log "fetching pinned binaries${GHPROXY:+ via $GHPROXY}"
	fetch() {
		local url="$1" out="$2"
		curl -fL --retry 3 --retry-delay 2 --connect-timeout 20 --max-time 600 \
			-o "$out" "${GHPROXY}${url}"
	}
	fetch "$PI_URL" "$WORK/$PI_ASSET"
	fetch "$FD_URL" "$WORK/$FD_ASSET"
	fetch "$RG_URL" "$WORK/$RG_ASSET"
	echo "$PI_SHA256  $WORK/$PI_ASSET" | sha256sum -c - >/dev/null
	echo "$FD_SHA256  $WORK/$FD_ASSET" | sha256sum -c - >/dev/null
	echo "$RG_SHA256  $WORK/$RG_ASSET" | sha256sum -c - >/dev/null
	tar xzf "$WORK/$PI_ASSET" --no-same-owner -C "$WORK"
	tar xzf "$WORK/$FD_ASSET" --no-same-owner -C "$WORK"
	tar xzf "$WORK/$RG_ASSET" --no-same-owner -C "$WORK"
	VENDOR_PI="$WORK/pi"
	VENDOR_FD="$(find "$WORK" -path '*/fd-*/fd' -type f | head -n1)"
	VENDOR_RG="$(find "$WORK" -path '*/ripgrep-*/rg' -type f | head -n1)"
	[ -x "$VENDOR_PI/pi" ] && [ -x "$VENDOR_FD" ] && [ -x "$VENDOR_RG" ] \
		|| die "failed to extract fetched binaries"
fi

# --- install layout ----------------------------------------------------------
VDIR="$PREFIX/$PKG_VERSION"
log "installing $PKG_VERSION into $VDIR"
mkdir -p "$PREFIX" "$BIN_DIR"
rm -rf "$VDIR"
mkdir -p "$VDIR/bin" "$VDIR/lib" "$VDIR/config"

cp -a --no-preserve=ownership "$VENDOR_PI" "$VDIR/pi"
install -m 0755 "$VENDOR_FD" "$VDIR/bin/fd"
install -m 0755 "$VENDOR_RG" "$VDIR/bin/rg"
ln -sfn ../pi/pi "$VDIR/bin/pi"

cp "$SELF_DIR/install.sh" "$SELF_DIR/uninstall.sh" "$VDIR/"
if [ -f "$SELF_DIR/versions.env" ]; then cp "$SELF_DIR/versions.env" "$VDIR/"; fi
cp -a --no-preserve=ownership "$SELF_DIR/lib/." "$VDIR/lib/"
cp -a --no-preserve=ownership "$SELF_DIR/config/." "$VDIR/config/"
cp -a --no-preserve=ownership "$SELF_DIR/bin/." "$VDIR/bin/"
printf '%s\n' "$PKG_VERSION" >"$VDIR/VERSION"
printf '%s\n' "$PI_VERSION" >"$VDIR/PI_VERSION"
chmod 0755 "$VDIR/install.sh" "$VDIR/uninstall.sh" "$VDIR/bin/hiascend-agent" "$VDIR/lib/doctor.sh"

# --- Python environment (offline) -------------------------------------------
log "creating Python environment"
if ! "$PYTHON" -m venv "$VDIR/venv" >/dev/null 2>&1; then
	"$PYTHON" -m venv --without-pip "$VDIR/venv"
	"$VDIR/venv/bin/python" -m ensurepip --upgrade >/dev/null 2>&1 \
		|| die "cannot bootstrap pip in $VDIR/venv"
fi
"$VDIR/venv/bin/python" -m pip install --disable-pip-version-check --no-index \
	--find-links "$WHEELS_DIR" "gitcode-api[mcp]==${GITCODE_API_VERSION:-1.3.4}" \
	|| die "offline installation of gitcode-api failed"

# --- render configuration ----------------------------------------------------
log "rendering configuration for prefix $PREFIX"
"$VDIR/venv/bin/python" - "$PREFIX" "$VDIR/config" <<'PY'
import pathlib, sys

prefix, config_dir = sys.argv[1], pathlib.Path(sys.argv[2])
for name in ("settings.json.in", "mcp.json.in"):
    src = config_dir / name
    if not src.exists():
        continue
    text = src.read_text(encoding="utf-8").replace("__PREFIX__", prefix)
    src.with_name(name[:-3]).write_text(text, encoding="utf-8")
    src.unlink()
PY

# --- activate version --------------------------------------------------------
ln -sfn "$PKG_VERSION" "$PREFIX/current"

cat >"$BIN_DIR/hiascend-agent" <<EOF
#!/bin/sh
exec "$PREFIX/current/bin/hiascend-agent" "\$@"
EOF
chmod 0755 "$BIN_DIR/hiascend-agent"

# --- merge Pi configuration --------------------------------------------------
log "merging Pi configuration into $PI_DIR"
mkdir -p "$PI_DIR"
"$VDIR/venv/bin/python" "$VDIR/lib/merge-config.py" --system "$VDIR/config" --user "$PI_DIR"

# --- SSH key + git identity --------------------------------------------------
if [ "$NO_SSH_KEYGEN" = 0 ]; then
	SSH_DIR="$HOME/.ssh"
	mkdir -p "$SSH_DIR"
	chmod 700 "$SSH_DIR" 2>/dev/null || true
	if [ ! -f "$SSH_DIR/id_ed25519" ]; then
		if command -v ssh-keygen >/dev/null 2>&1; then
			ssh-keygen -t ed25519 -N '' -C "hiascend-agent@$(hostname)" -f "$SSH_DIR/id_ed25519" >/dev/null
			log "generated SSH key: $SSH_DIR/id_ed25519"
		else
			warn "ssh-keygen not found; skipping SSH key generation"
		fi
	fi
fi

if [ "$NO_GIT_CONFIG" = 0 ] && command -v git >/dev/null 2>&1; then
	git config --global user.name "${GIT_AUTHOR_NAME:-${GIT_USER_NAME:-hiascend-agent}}"
	git config --global user.email "${GIT_AUTHOR_EMAIL:-${GIT_USER_EMAIL:-hiascend-agent@localhost}}"
	git config --global --add safe.directory '*' 2>/dev/null || true
fi

# --- report ------------------------------------------------------------------
log "installed: $VDIR"
log "launcher : $BIN_DIR/hiascend-agent"
log "config   : $PI_DIR"
if [ -f "$HOME/.ssh/id_ed25519.pub" ]; then
	log "register this SSH key at https://gitcode.com/setting/key-ssh :"
	sed 's/^/    /' "$HOME/.ssh/id_ed25519.pub"
fi
log "add the GitCode token with: export GITCODE_ACCESS_TOKEN=..."
log "then run: hiascend-agent doctor"

if [ "$NO_DOCTOR" = 0 ]; then
	"$VDIR/bin/hiascend-agent" doctor || true
fi
