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

FLUTTER_ROOT="${FLUTTER_DIR:-$HOME/development}/flutter"
FLUTTER_BIN="$FLUTTER_ROOT/bin/flutter"

if [ ! -x "$FLUTTER_BIN" ]; then
    echo "⏭️  Skipping Flutter update: the repository-managed SDK is not installed under $FLUTTER_ROOT."
    exit 0
fi

BEFORE_VERSION=$("$FLUTTER_BIN" --version 2>/dev/null | head -1 || true)
echo "🚀 Updating Flutter (${BEFORE_VERSION:-version unknown})..."
"$FLUTTER_BIN" upgrade
AFTER_VERSION=$("$FLUTTER_BIN" --version 2>/dev/null | head -1 || true)
echo "✅ Flutter updated: ${BEFORE_VERSION:-unknown} → ${AFTER_VERSION:-unknown}"
