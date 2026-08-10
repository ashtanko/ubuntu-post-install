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

echo "🚀 Installing Warp terminal..."

ARCH=$(dpkg --print-architecture 2>/dev/null || uname -m)
if [ "$ARCH" != "amd64" ] && [ "$ARCH" != "x86_64" ]; then
    echo "❌ This Warp repository configuration supports amd64 only (detected: $ARCH)."
    exit 1
fi

if command -v warp-terminal &>/dev/null; then
    echo "✅ Warp terminal already installed"
    exit 0
fi

# Temp file cleaned up on exit regardless of outcome
GPG_TMP=$(mktemp --suffix=.gpg)
trap 'rm -f "$GPG_TMP"' EXIT

echo "📦 Adding Warp GPG key and repository..."
sudo apt-get install -y wget gpg

wget --tries=3 --waitretry=2 -qO- https://releases.warp.dev/linux/keys/warp.asc | gpg --dearmor > "$GPG_TMP"
sudo install -D -o root -g root -m 644 "$GPG_TMP" /etc/apt/keyrings/warpdotdev.gpg

sudo sh -c 'echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/warpdotdev.gpg] https://releases.warp.dev/linux/deb stable main" \
    > /etc/apt/sources.list.d/warpdotdev.list'

echo "📦 Installing Warp terminal..."
sudo apt update
sudo apt install -y warp-terminal

if command -v warp-terminal &>/dev/null; then
    echo "✅ Warp terminal installed successfully"
else
    echo "❌ Warp installation failed"
    exit 1
fi
