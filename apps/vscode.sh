#!/bin/bash
set -euo pipefail

# Re-exec under bash if invoked via `sh` (dash mishandles &>, [[ ]], etc.)
if [ -z "${BASH_VERSION:-}" ]; then
    exec /bin/bash "$0" "$@"
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ -f "$REPO_ROOT/.env" ]] && { set -a; source "$REPO_ROOT/.env"; set +a; }

echo "🚀 Installing Visual Studio Code..."

if command -v code &>/dev/null; then
    echo "✅ VS Code already installed ($(code --version | head -1))"
    exit 0
fi

# Temp GPG file cleaned up on exit
GPG_TMP=$(mktemp --suffix=.gpg)
trap 'rm -f "$GPG_TMP"' EXIT

echo "📦 Adding Microsoft GPG key and repository..."
sudo apt update
sudo apt install -y wget gpg apt-transport-https

wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > "$GPG_TMP"
sudo install -D -o root -g root -m 644 "$GPG_TMP" /etc/apt/keyrings/packages.microsoft.gpg

# Add repo only if not already present
if [ ! -f /etc/apt/sources.list.d/vscode.list ]; then
    echo "deb [arch=amd64,arm64,armhf signed-by=/etc/apt/keyrings/packages.microsoft.gpg] \
https://packages.microsoft.com/repos/code stable main" \
        | sudo tee /etc/apt/sources.list.d/vscode.list > /dev/null
fi

echo "📦 Installing VS Code..."
sudo apt update
sudo apt install -y code

if command -v code &>/dev/null; then
    echo "✅ VS Code installed ($(code --version | head -1))"
else
    echo "❌ VS Code installation failed"
    exit 1
fi
