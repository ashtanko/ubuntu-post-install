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
    echo "⏭️  Visual Studio Code is not installed; skipping extension updates."
    exit 0
fi

if ! dpkg-query -W -f='${Status}' code 2>/dev/null | grep -q 'ok installed'; then
    echo "⏭️  Visual Studio Code is not managed by the Debian package installed by this project; skipping extension updates."
    exit 0
fi

if ! dpkg-query -S "$CODE_BIN" 2>/dev/null | grep -q '^code:'; then
    echo "⏭️  The active Visual Studio Code executable is not owned by the code Debian package; skipping extension updates."
    exit 0
fi

BEFORE_VERSION=$("$CODE_BIN" --version 2>/dev/null | head -n1 || echo "version unknown")
echo "🚀 Updating installed Visual Studio Code extensions..."
echo "   VS Code: $BEFORE_VERSION"

"$CODE_BIN" --update-extensions

AFTER_VERSION=$("$CODE_BIN" --version 2>/dev/null | head -n1 || echo "version unknown")
echo "✅ Visual Studio Code extension update complete"
echo "   VS Code: $AFTER_VERSION"
