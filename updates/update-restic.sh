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

RESTIC_BIN="$(command -v restic 2>/dev/null || true)"
if [ -z "$RESTIC_BIN" ]; then
    echo "⏭️  Skipping restic update: restic is not installed."
    exit 0
fi

if [ "$RESTIC_BIN" != "/usr/local/bin/restic" ]; then
    echo "⏭️  Skipping restic update: $RESTIC_BIN is not the standalone binary installed by this repository."
    exit 0
fi

BEFORE_VERSION=$("$RESTIC_BIN" version 2>/dev/null | head -1 || true)
echo "🚀 Updating restic (${BEFORE_VERSION:-version unknown})..."
if [ -w "$RESTIC_BIN" ]; then
    "$RESTIC_BIN" self-update
else
    sudo "$RESTIC_BIN" self-update
fi
AFTER_VERSION=$("$RESTIC_BIN" version 2>/dev/null | head -1 || true)
echo "✅ restic updated: ${BEFORE_VERSION:-unknown} → ${AFTER_VERSION:-unknown}"
