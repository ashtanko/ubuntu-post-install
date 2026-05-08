#!/bin/bash
set -euo pipefail

# Re-exec under bash if invoked via `sh` (dash mishandles &>, [[ ]], etc.)
if [ -z "${BASH_VERSION:-}" ]; then
    exec /bin/bash "$0" "$@"
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ -f "$REPO_ROOT/.env" ]] && { set -a; source "$REPO_ROOT/.env"; set +a; }

echo "🚀 Installing Gemini CLI..."

# Ensure Node.js 18+ is available
if command -v node &>/dev/null; then
    NODE_MAJOR=$(node -v | cut -dv -f2 | cut -d. -f1)
    if [ "$NODE_MAJOR" -lt 18 ]; then
        echo "❌ Node.js $(node -v) is too old. Gemini CLI requires v18+."
        echo "💡 Run dev/node.sh to install a modern version via NVM."
        exit 1
    fi
    echo "✅ Node.js $(node -v) found"
else
    echo "📦 Node.js not found — installing v20 LTS via NodeSource (verified GPG repo)..."

    GPG_TMP=$(mktemp --suffix=.gpg)
    trap 'rm -f "$GPG_TMP"' EXIT

    sudo apt-get install -y wget gpg ca-certificates

    wget -qO- https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
        | gpg --dearmor > "$GPG_TMP"
    sudo install -D -o root -g root -m 644 "$GPG_TMP" /etc/apt/keyrings/nodesource.gpg

    echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_20.x nodistro main" \
        | sudo tee /etc/apt/sources.list.d/nodesource.list > /dev/null

    sudo apt-get update
    sudo apt-get install -y nodejs

    if ! command -v node &>/dev/null; then
        echo "❌ Node.js install failed"
        exit 1
    fi

    # On newer Ubuntu (e.g. 26.04) the distro nodejs package wins the version
    # comparison against NodeSource and ships without npm — pull npm separately.
    if ! command -v npm &>/dev/null; then
        echo "📦 Installing npm separately (distro nodejs doesn't bundle it)..."
        sudo apt-get install -y npm
    fi

    echo "✅ Node.js $(node -v) installed"
fi

# Install Gemini CLI globally
if command -v gemini &>/dev/null; then
    echo "✅ Gemini CLI already installed ($(gemini --version 2>/dev/null || echo 'version unknown'))"
    echo "💡 Update with: sudo npm update -g @google/gemini-cli"
    exit 0
fi

echo "📦 Installing @google/gemini-cli..."
sudo npm install -g @google/gemini-cli

if command -v gemini &>/dev/null; then
    echo "✅ Gemini CLI installed successfully!"
    echo ""
    echo "💡 Next step: run 'gemini' to authenticate via your Google account"
else
    echo "❌ Installation failed or 'gemini' is not in PATH"
    exit 1
fi
