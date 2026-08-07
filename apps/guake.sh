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

echo "🚀 Installing Guake terminal..."

if command -v guake &>/dev/null; then
    echo "✅ Guake already installed"
    exit 0
fi

sudo apt update
sudo apt install -y guake

if command -v guake &>/dev/null; then
    echo "✅ Guake installed successfully"
    echo "💡 Launch Guake from the application menu, then press F12 to open/close"
else
    echo "❌ Guake installation failed"
    exit 1
fi
