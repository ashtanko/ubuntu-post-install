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

if ! command -v dpkg-query >/dev/null 2>&1; then
    echo "⏭️  dpkg is unavailable, so no APT-managed Antigravity is installed; skipping update."
    exit 0
fi

if ! dpkg-query -W -f='${Status}' antigravity 2>/dev/null | grep -q 'ok installed'; then
    echo "⏭️  Antigravity is not installed from the APT package this project configures; skipping update."
    exit 0
fi

# The installed package is the ownership proof: /usr/bin/antigravity is a
# postinst-created symlink into /usr/share/antigravity, so it is not in dpkg's
# file list and `dpkg-query -S` on it would wrongly report a foreign install.
# Versions are read from the package database rather than by launching the
# Electron binary, which needs a display.
BEFORE_VERSION=$(dpkg-query -W -f='${Version}' antigravity 2>/dev/null || true)
echo "🚀 Updating Antigravity..."
echo "   Before: ${BEFORE_VERSION:-version unknown}"

sudo apt-get update
sudo apt-get install -y --only-upgrade antigravity

AFTER_VERSION=$(dpkg-query -W -f='${Version}' antigravity 2>/dev/null || true)
echo "✅ Antigravity update complete"
echo "   After:  ${AFTER_VERSION:-version unknown}"
