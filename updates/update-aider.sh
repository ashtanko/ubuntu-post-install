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

AIDER_BIN="$HOME/.local/bin/aider"
if [ ! -x "$AIDER_BIN" ]; then
    echo "⏭️  Skipping Aider update: the repository-managed binary was not found at $AIDER_BIN."
    exit 0
fi

BEFORE_VERSION=$("$AIDER_BIN" --version 2>/dev/null | head -1 || true)
echo "🚀 Updating Aider (${BEFORE_VERSION:-version unknown})..."
"$AIDER_BIN" --upgrade
AFTER_VERSION=$("$AIDER_BIN" --version 2>/dev/null | head -1 || true)
echo "✅ Aider updated: ${BEFORE_VERSION:-unknown} → ${AFTER_VERSION:-unknown}"
