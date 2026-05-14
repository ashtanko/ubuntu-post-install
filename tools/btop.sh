#!/bin/bash
set -euo pipefail

# Re-exec under bash if invoked via `sh` (dash mishandles &>, [[ ]], etc.)
if [ -z "${BASH_VERSION:-}" ]; then
    exec /bin/bash "$0" "$@"
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ -f "$REPO_ROOT/.env" ]] && { set -a; source "$REPO_ROOT/.env"; set +a; }

echo "🚀 Installing btop resource monitor..."

if command -v btop &>/dev/null; then
    echo "✅ btop already installed"
    exit 0
fi

echo "📦 Installing btop..."
sudo apt update
sudo apt install -y btop

if command -v btop &>/dev/null; then
    echo "✅ btop installed successfully"
    echo "💡 Launch it by running: btop"
else
    echo "❌ btop installation failed"
    exit 1
fi
