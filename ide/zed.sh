#!/bin/bash
set -euo pipefail

# Re-exec under bash if invoked via `sh` (dash mishandles &>, [[ ]], etc.)
if [ -z "${BASH_VERSION:-}" ]; then
    exec /bin/bash "$0" "$@"
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ -f "$REPO_ROOT/.env" ]] && { set -a; source "$REPO_ROOT/.env"; set +a; }

echo "🚀 Installing Zed IDE..."

ZED_BIN="$HOME/.local/bin/zed"
if [[ -f "$ZED_BIN" ]] && "$ZED_BIN" --version 2>/dev/null | grep -qi "zed"; then
    echo "✅ Zed already installed ($("$ZED_BIN" --version 2>/dev/null || echo 'version unknown'))"
    exit 0
fi

echo "📦 Installing Zed (preview channel) via official install script..."
curl -f https://zed.dev/install.sh | ZED_CHANNEL=preview sh

if [ -f "$ZED_BIN" ]; then
    echo "✅ Zed installed successfully!"
    echo "💡 Launch with: zed"
else
    echo "❌ Zed installation failed"
    exit 1
fi
