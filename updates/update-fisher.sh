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

if ! command -v fish &>/dev/null || ! fish -c 'type -q fisher' &>/dev/null; then
    echo "⏭️  Skipping Fisher update: Fisher is not installed."
    exit 0
fi

BEFORE_VERSION=$(fish -c 'fisher --version' 2>/dev/null | head -1 || true)
echo "🚀 Updating Fisher and installed plugins (${BEFORE_VERSION:-version unknown})..."
fish -c 'fisher update'
AFTER_VERSION=$(fish -c 'fisher --version' 2>/dev/null | head -1 || true)
echo "✅ Fisher updated: ${BEFORE_VERSION:-unknown} → ${AFTER_VERSION:-unknown}"
