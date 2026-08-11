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

CURSOR_AGENT_BIN="$HOME/.local/bin/cursor-agent"
if [ ! -x "$CURSOR_AGENT_BIN" ]; then
    echo "⏭️  Skipping Cursor Agent update: the repository-managed binary was not found at $CURSOR_AGENT_BIN."
    exit 0
fi

BEFORE_VERSION=$("$CURSOR_AGENT_BIN" --version 2>/dev/null | head -1 || true)
echo "🚀 Updating Cursor Agent (${BEFORE_VERSION:-version unknown})..."
"$CURSOR_AGENT_BIN" update
AFTER_VERSION=$("$CURSOR_AGENT_BIN" --version 2>/dev/null | head -1 || true)
echo "✅ Cursor Agent updated: ${BEFORE_VERSION:-unknown} → ${AFTER_VERSION:-unknown}"
