#!/bin/bash
set -euo pipefail

# Re-exec under bash if invoked via `sh` (dash mishandles &>, [[ ]], etc.)
if [ -z "${BASH_VERSION:-}" ]; then
    exec /bin/bash "$0" "$@"
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ -f "$REPO_ROOT/.env" ]] && { set -a; source "$REPO_ROOT/.env"; set +a; }

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
