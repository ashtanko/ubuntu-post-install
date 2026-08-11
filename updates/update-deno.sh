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

DENO_DIR="${DENO_INSTALL:-$HOME/.deno}"
DENO_BIN="$DENO_DIR/bin/deno"
if [ ! -x "$DENO_BIN" ]; then
    echo "⏭️  Deno is not installed under $DENO_DIR; skipping update."
    exit 0
fi

BEFORE_VERSION=$("$DENO_BIN" --version 2>/dev/null | head -n 1 || true)
echo "🚀 Updating Deno..."
echo "   Before: ${BEFORE_VERSION:-version unknown}"

"$DENO_BIN" upgrade --quiet

AFTER_VERSION=$("$DENO_BIN" --version 2>/dev/null | head -n 1 || true)
echo "✅ Deno update complete"
echo "   After:  ${AFTER_VERSION:-version unknown}"
