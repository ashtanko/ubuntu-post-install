#!/bin/bash
set -euo pipefail

# Re-exec under bash if invoked via `sh` (dash mishandles &>, [[ ]], etc.)
if [ -z "${BASH_VERSION:-}" ]; then
    exec /bin/bash "$0" "$@"
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_HELPER="$REPO_ROOT/lib/config.bash"
# shellcheck source=lib/config.bash
source "$CONFIG_HELPER" || { echo "❌ Missing config helper: $CONFIG_HELPER" >&2; exit 1; }
load_config "$REPO_ROOT"

RCLONE_BIN="$(command -v rclone 2>/dev/null || true)"
if [ -z "$RCLONE_BIN" ]; then
    echo "⏭️  Skipping rclone update: rclone is not installed."
    exit 0
fi

RCLONE_BIN="$(readlink -f "$RCLONE_BIN")"
if [ "$RCLONE_BIN" != "/usr/bin/rclone" ]; then
    echo "⏭️  Skipping rclone update: $RCLONE_BIN is not the standalone binary installed by this repository."
    exit 0
fi

if dpkg-query -S "$RCLONE_BIN" &>/dev/null; then
    echo "⏭️  Skipping rclone update: $RCLONE_BIN is owned by a Debian package."
    exit 0
fi

BEFORE_VERSION=$("$RCLONE_BIN" version 2>/dev/null | head -1 || true)
echo "🚀 Updating rclone (${BEFORE_VERSION:-version unknown})..."
if [ -w "$RCLONE_BIN" ]; then
    "$RCLONE_BIN" selfupdate --stable
else
    sudo "$RCLONE_BIN" selfupdate --stable
fi
AFTER_VERSION=$("$RCLONE_BIN" version 2>/dev/null | head -1 || true)
echo "✅ rclone updated: ${BEFORE_VERSION:-unknown} → ${AFTER_VERSION:-unknown}"
