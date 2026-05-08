#!/bin/bash
set -euo pipefail

# Re-exec under bash if invoked via `sh` (dash mishandles &>, [[ ]], etc.)
if [ -z "${BASH_VERSION:-}" ]; then
    exec /bin/bash "$0" "$@"
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ -f "$REPO_ROOT/.env" ]] && { set -a; source "$REPO_ROOT/.env"; set +a; }

echo "🚀 Installing VirtualBox..."

if command -v virtualbox &>/dev/null; then
    echo "✅ VirtualBox already installed"
    exit 0
fi

echo "📦 Installing virtualbox + extension pack..."
sudo apt update
sudo apt install -y virtualbox virtualbox-ext-pack

if command -v virtualbox &>/dev/null; then
    echo "✅ VirtualBox installed"
    echo "💡 You may need to add yourself to the vboxusers group:"
    echo "     sudo usermod -aG vboxusers \"\$USER\""
else
    echo "❌ VirtualBox installation failed"
    exit 1
fi
