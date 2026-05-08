#!/bin/bash
set -euo pipefail

# Re-exec under bash if invoked via `sh` (dash mishandles &>, [[ ]], etc.)
if [ -z "${BASH_VERSION:-}" ]; then
    exec /bin/bash "$0" "$@"
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ -f "$REPO_ROOT/.env" ]] && { set -a; source "$REPO_ROOT/.env"; set +a; }

echo "🚀 Setting up browsers..."

# --- Google Chrome ---
if command -v google-chrome &>/dev/null; then
    echo "✅ Google Chrome already installed ($(google-chrome --version))"
else
    echo "📦 Installing Google Chrome..."
    DEB=$(mktemp --suffix=.deb)
    trap 'rm -f "$DEB"' EXIT

    wget -q --show-progress -O "$DEB" \
        "https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb"

    sudo apt update
    sudo apt install -y "$DEB"

    if command -v google-chrome &>/dev/null; then
        echo "✅ Google Chrome installed ($(google-chrome --version))"
    else
        echo "❌ Chrome installation failed"
        exit 1
    fi
fi
