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

CLINE_BIN="$(command -v cline 2>/dev/null || true)"
if [ -z "$CLINE_BIN" ]; then
    echo "⏭️  Skipping Cline update: Cline CLI is not installed."
    exit 0
fi

CLINE_VERSION="${CLINE_VERSION:-latest}"
if [ "$CLINE_VERSION" != "latest" ]; then
    echo "⏭️  Skipping Cline update: CLINE_VERSION is pinned to '$CLINE_VERSION'."
    exit 0
fi

NPM_BIN="$(command -v npm 2>/dev/null || true)"
if [ -z "$NPM_BIN" ]; then
    echo "⏭️  Skipping Cline update: the active Cline binary cannot be verified without npm."
    exit 0
fi

NPM_ROOT=$("$NPM_BIN" root -g 2>/dev/null || true)
if [ -z "$NPM_ROOT" ] || [ ! -d "$NPM_ROOT/cline" ]; then
    echo "⏭️  Skipping Cline update: the active npm installation does not own a global cline package."
    exit 0
fi

CLINE_REAL=$(readlink -f "$CLINE_BIN")
CLINE_PACKAGE_DIR=$(readlink -f "$NPM_ROOT/cline")
case "$CLINE_REAL" in
    "$CLINE_PACKAGE_DIR"/*) ;;
    *)
        echo "⏭️  Skipping Cline update: $CLINE_BIN does not belong to the active npm global cline package."
        exit 0
        ;;
esac

BEFORE_VERSION=$("$CLINE_BIN" --version 2>/dev/null | head -1 || true)
echo "🚀 Updating Cline CLI (${BEFORE_VERSION:-version unknown})..."
"$CLINE_BIN" update
AFTER_VERSION=$("$CLINE_BIN" --version 2>/dev/null | head -1 || true)
echo "✅ Cline CLI updated: ${BEFORE_VERSION:-unknown} → ${AFTER_VERSION:-unknown}"
