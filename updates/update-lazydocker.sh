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

LAZYDOCKER_BIN="$(command -v lazydocker 2>/dev/null || true)"
if [ -z "$LAZYDOCKER_BIN" ]; then
    echo "⏭️  Skipping lazydocker update: lazydocker is not installed."
    exit 0
fi

LAZYDOCKER_BIN="$(readlink -f "$LAZYDOCKER_BIN" 2>/dev/null || true)"
if [ "$LAZYDOCKER_BIN" != "/usr/local/bin/lazydocker" ]; then
    echo "⏭️  Skipping lazydocker update: ${LAZYDOCKER_BIN:-the active binary} is not the standalone binary installed by this repository."
    exit 0
fi

if command -v dpkg-query &>/dev/null && dpkg-query -S "$LAZYDOCKER_BIN" &>/dev/null; then
    echo "⏭️  Skipping lazydocker update: $LAZYDOCKER_BIN is owned by a Debian package."
    exit 0
fi

BEFORE_VERSION=$("$LAZYDOCKER_BIN" --version 2>/dev/null | head -1 || true)
echo "🚀 Updating lazydocker..."
echo "   Before: ${BEFORE_VERSION:-version unknown}"

UPI_LAZYDOCKER_UPDATE=1 /bin/bash "$REPO_ROOT/tools/lazydocker.sh"

if [ ! -x "$LAZYDOCKER_BIN" ]; then
    echo "❌ lazydocker was not found at $LAZYDOCKER_BIN after the update" >&2
    exit 1
fi

AFTER_VERSION=$("$LAZYDOCKER_BIN" --version 2>/dev/null | head -1 || true)
echo "✅ lazydocker update complete"
echo "   After:  ${AFTER_VERSION:-version unknown}"
