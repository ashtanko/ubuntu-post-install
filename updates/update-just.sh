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

JUST_BIN="$(command -v just 2>/dev/null || true)"
if [ -z "$JUST_BIN" ]; then
    echo "⏭️  Skipping just update: just is not installed."
    exit 0
fi

JUST_BIN="$(readlink -f "$JUST_BIN" 2>/dev/null || true)"
if [ "$JUST_BIN" != "/usr/local/bin/just" ]; then
    echo "⏭️  Skipping just update: ${JUST_BIN:-the active binary} is not the standalone binary installed by this repository."
    exit 0
fi

if command -v dpkg-query &>/dev/null && dpkg-query -S "$JUST_BIN" &>/dev/null; then
    echo "⏭️  Skipping just update: $JUST_BIN is owned by a Debian package."
    exit 0
fi

BEFORE_VERSION=$("$JUST_BIN" --version 2>/dev/null | head -1 || true)
echo "🚀 Updating just..."
echo "   Before: ${BEFORE_VERSION:-version unknown}"

UPI_JUST_UPDATE=1 /bin/bash "$REPO_ROOT/tools/just.sh"

if [ ! -x "$JUST_BIN" ]; then
    echo "❌ just was not found at $JUST_BIN after the update" >&2
    exit 1
fi

AFTER_VERSION=$("$JUST_BIN" --version 2>/dev/null | head -1 || true)
echo "✅ just update complete"
echo "   After:  ${AFTER_VERSION:-version unknown}"
