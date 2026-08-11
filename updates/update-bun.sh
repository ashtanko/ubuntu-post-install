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

BUN_DIR="${BUN_INSTALL:-$HOME/.bun}"
BUN_BIN="$BUN_DIR/bin/bun"
if [ ! -x "$BUN_BIN" ]; then
    echo "⏭️  Bun is not installed under $BUN_DIR; skipping update."
    exit 0
fi

BEFORE_VERSION=$("$BUN_BIN" --version 2>/dev/null | head -n 1 || true)
echo "🚀 Updating Bun..."
echo "   Before: ${BEFORE_VERSION:-version unknown}"

"$BUN_BIN" upgrade

AFTER_VERSION=$("$BUN_BIN" --version 2>/dev/null | head -n 1 || true)
echo "✅ Bun update complete"
echo "   After:  ${AFTER_VERSION:-version unknown}"
