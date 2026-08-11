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

echo "🚀 Setting up browsers..."

ARCH=$(dpkg --print-architecture 2>/dev/null || uname -m)
if [ "$ARCH" != "amd64" ] && [ "$ARCH" != "x86_64" ]; then
    echo "❌ Google Chrome's bundled installer supports amd64 only (detected: $ARCH)."
    exit 1
fi

# --- Google Chrome ---
if command -v google-chrome &>/dev/null; then
    echo "✅ Google Chrome already installed ($(google-chrome --version))"
else
    echo "📦 Installing Google Chrome..."
    DEB=$(mktemp --suffix=.deb)
    trap 'rm -f "$DEB"' EXIT

    wget --tries=3 --waitretry=2 -nv --show-progress -O "$DEB" \
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
