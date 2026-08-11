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

if ! CODE_BIN=$(command -v code); then
    echo "⏭️  Visual Studio Code is not installed; skipping update."
    exit 0
fi

if ! dpkg-query -W -f='${Status}' code 2>/dev/null | grep -q 'ok installed'; then
    echo "⏭️  Visual Studio Code is not managed by the Microsoft APT package installed by this project; skipping update."
    exit 0
fi

if ! dpkg-query -S "$CODE_BIN" 2>/dev/null | grep -q '^code:'; then
    echo "⏭️  The active code executable is not owned by the code APT package; skipping update."
    exit 0
fi

BEFORE_VERSION=$("$CODE_BIN" --version 2>/dev/null | head -1 || true)
echo "🚀 Updating Visual Studio Code..."
echo "   Before: ${BEFORE_VERSION:-version unknown}"

sudo apt-get update
sudo apt-get install -y --only-upgrade code

AFTER_VERSION=$("$CODE_BIN" --version 2>/dev/null | head -1 || true)
echo "✅ Visual Studio Code update complete"
echo "   After:  ${AFTER_VERSION:-version unknown}"
