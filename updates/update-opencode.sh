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

OPENCODE_INSTALL_DIR="${OPENCODE_INSTALL_DIR:-$HOME/.opencode}"
# The native curl-method upgrader re-runs the upstream installer, which reads
# its destination from the child-process environment.
export OPENCODE_INSTALL_DIR
OPENCODE_BIN="$OPENCODE_INSTALL_DIR/bin/opencode"

if [ ! -x "$OPENCODE_BIN" ]; then
    echo "⏭️  The opencode installation managed by this project was not found; skipping update."
    exit 0
fi

BEFORE_VERSION=$("$OPENCODE_BIN" --version 2>/dev/null || echo "version unknown")
echo "🚀 Updating opencode..."
echo "   Before: $BEFORE_VERSION"

"$OPENCODE_BIN" upgrade --method curl

if [ ! -x "$OPENCODE_BIN" ]; then
    echo "❌ opencode is no longer available after the update" >&2
    exit 1
fi

AFTER_VERSION=$("$OPENCODE_BIN" --version 2>/dev/null || echo "version unknown")
echo "✅ opencode update complete"
echo "   After:  $AFTER_VERSION"
