#!/usr/bin/env bash
# =============================================================================
# hiascend-agent uninstaller
#
# Removes one installed version (the one this script belongs to), updates the
# `current` symlink, and optionally removes the package's entries from the Pi
# configuration. User configuration is kept unless --purge-config is given.
#
#   ./uninstall.sh
#   ./uninstall.sh --prefix /opt/hiascend-agent --purge-config
# =============================================================================
set -euo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION="$(cat "$SELF_DIR/VERSION" 2>/dev/null || echo '')"

PREFIX="/opt/hiascend-agent"
BIN_DIR="/usr/local/bin"
PI_DIR="${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}"
PURGE_CONFIG=0

# If invoked from an installed version directory, derive the install root.
if [ -n "$VERSION" ] && [ "$(basename "$SELF_DIR")" = "$VERSION" ]; then
	PREFIX="$(cd "$SELF_DIR/.." && pwd)"
fi

while [ $# -gt 0 ]; do
	case "$1" in
		--prefix) PREFIX="${2:?}"; shift 2 ;;
		--bin-dir) BIN_DIR="${2:?}"; shift 2 ;;
		--pi-dir) PI_DIR="${2:?}"; shift 2 ;;
		--purge-config) PURGE_CONFIG=1; shift ;;
		-h|--help) sed -n '2,14p' "$0"; exit 0 ;;
		*) echo "unknown option: $1" >&2; exit 2 ;;
	esac
done

[ -n "$VERSION" ] || { echo "cannot determine version (VERSION file missing)" >&2; exit 1; }

warn() { printf '\033[33mwarning:\033[0m %s\n' "$*" >&2; }
log() { printf '\033[36m[uninstall]\033[0m %s\n' "$*"; }

TARGET="$PREFIX/$VERSION"
[ -d "$TARGET" ] || warn "not installed: $TARGET"

# Remove package entries from the user's Pi config (before deleting the files).
if [ "$PURGE_CONFIG" = 1 ]; then
	MERGE=""
	if [ -f "$SELF_DIR/lib/merge-config.py" ]; then
		MERGE="$SELF_DIR/lib/merge-config.py"
	elif [ -f "$TARGET/lib/merge-config.py" ]; then
		MERGE="$TARGET/lib/merge-config.py"
	fi
	PYTHON="$(command -v python3.11 || command -v python3 || true)"
	if [ -n "$MERGE" ] && [ -n "$PYTHON" ]; then
		log "removing package entries from $PI_DIR"
		"$PYTHON" "$MERGE" --remove --prefix "$PREFIX/" --user "$PI_DIR" || \
			warn "could not clean $PI_DIR settings"
	else
		warn "merge-config.py or python3 not found; leaving $PI_DIR untouched"
	fi
fi

# Determine what remains after removing this version.
remaining="$(find "$PREFIX" -mindepth 1 -maxdepth 1 -type d ! -name "$VERSION" -printf '%f\n' 2>/dev/null | sort | tail -n1 || true)"

if [ -L "$PREFIX/current" ]; then
	current_target="$(readlink "$PREFIX/current" || true)"
	if [ "$current_target" = "$VERSION" ] || [ ! -e "$PREFIX/current" ]; then
		if [ -n "$remaining" ]; then
			ln -sfn "$remaining" "$PREFIX/current"
			log "current -> $remaining"
		else
			rm -f "$PREFIX/current"
		fi
	fi
fi

# Remove the launcher only when no installed version remains.
if [ -z "$remaining" ] && [ -f "$BIN_DIR/hiascend-agent" ]; then
	if grep -q "$PREFIX" "$BIN_DIR/hiascend-agent" 2>/dev/null; then
		rm -f "$BIN_DIR/hiascend-agent"
		log "removed launcher $BIN_DIR/hiascend-agent"
	fi
fi

# Delete the version directory last: this script may be running from it.
log "removing $TARGET"
rm -rf "$TARGET"

if [ "$PURGE_CONFIG" = 0 ]; then
	log "kept user configuration in $PI_DIR (use --purge-config to remove package entries)"
fi
log "done"
