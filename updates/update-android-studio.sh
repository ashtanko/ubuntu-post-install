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

if ! command -v snap &>/dev/null || ! snap list android-studio &>/dev/null; then
    echo "⏭️  Skipping Android Studio update: the android-studio snap is not installed."
    exit 0
fi

BEFORE_VERSION=$(snap list android-studio 2>/dev/null | awk 'NR == 2 {print $2}')
echo "🚀 Updating Android Studio (${BEFORE_VERSION:-version unknown})..."
sudo snap refresh android-studio
AFTER_VERSION=$(snap list android-studio 2>/dev/null | awk 'NR == 2 {print $2}')
echo "✅ Android Studio updated: ${BEFORE_VERSION:-unknown} → ${AFTER_VERSION:-unknown}"
