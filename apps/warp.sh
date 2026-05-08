#!/bin/bash
set -euo pipefail

# Re-exec under bash if invoked via `sh` (dash mishandles &>, [[ ]], etc.)
if [ -z "${BASH_VERSION:-}" ]; then
    exec /bin/bash "$0" "$@"
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ -f "$REPO_ROOT/.env" ]] && { set -a; source "$REPO_ROOT/.env"; set +a; }

echo "🚀 Installing Warp terminal..."

if command -v warp-terminal &>/dev/null; then
    echo "✅ Warp terminal already installed"
    exit 0
fi

# Temp file cleaned up on exit regardless of outcome
GPG_TMP=$(mktemp --suffix=.gpg)
trap 'rm -f "$GPG_TMP"' EXIT

echo "📦 Adding Warp GPG key and repository..."
sudo apt-get install -y wget gpg

wget -qO- https://releases.warp.dev/linux/keys/warp.asc | gpg --dearmor > "$GPG_TMP"
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
