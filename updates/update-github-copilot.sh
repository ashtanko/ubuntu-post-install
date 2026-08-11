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

COPILOT_BIN="$HOME/.local/bin/copilot"
if [ ! -x "$COPILOT_BIN" ]; then
    echo "⏭️  Skipping GitHub Copilot CLI update: the repository-managed binary was not found at $COPILOT_BIN."
    exit 0
fi

COPILOT_VERSION="${COPILOT_VERSION:-latest}"
if [ "$COPILOT_VERSION" != "latest" ]; then
    echo "⏭️  Skipping GitHub Copilot CLI update: COPILOT_VERSION is pinned to '$COPILOT_VERSION'."
    exit 0
fi

BEFORE_VERSION=$("$COPILOT_BIN" version 2>/dev/null | head -1 || true)
echo "🚀 Updating GitHub Copilot CLI (${BEFORE_VERSION:-version unknown})..."
"$COPILOT_BIN" update
AFTER_VERSION=$("$COPILOT_BIN" version 2>/dev/null | head -1 || true)
echo "✅ GitHub Copilot CLI updated: ${BEFORE_VERSION:-unknown} → ${AFTER_VERSION:-unknown}"
