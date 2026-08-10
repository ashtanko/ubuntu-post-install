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

echo "🚀 Installing Claude Code CLI..."

# Ensure Node.js 18+ is available
if command -v node &>/dev/null; then
    NODE_MAJOR=$(node -v | cut -dv -f2 | cut -d. -f1)
    if [ "$NODE_MAJOR" -lt 18 ]; then
        echo "❌ Node.js $(node -v) is too old. Claude Code requires v18+."
        echo "💡 Run dev/node.sh to install a modern version via NVM."
        exit 1
    fi
    echo "✅ Node.js $(node -v) found"
else
    echo "📦 Node.js not found — installing v20 LTS via NodeSource (verified GPG repo)..."

    GPG_TMP=$(mktemp --suffix=.gpg)
    trap 'rm -f "$GPG_TMP"' EXIT

    sudo apt-get install -y wget gpg ca-certificates

    # Download NodeSource signing key, dearmor, install to keyrings
    wget --tries=3 --waitretry=2 -qO- https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
        | gpg --dearmor > "$GPG_TMP"
    sudo install -D -o root -g root -m 644 "$GPG_TMP" /etc/apt/keyrings/nodesource.gpg

    # Add the apt source pinned to the verified key
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

if ! command -v npm &>/dev/null; then
    echo "❌ npm is required but was not found after installing/checking Node.js."
    echo "💡 Install npm, or run dev/node.sh to install Node.js via NVM."
    exit 1
fi

NPM_BIN=$(type -P npm)
if [[ "$NPM_BIN" != /* ]]; then
    NPM_BIN="$(cd "$(dirname "$NPM_BIN")" && pwd)/${NPM_BIN##*/}"
fi
if ! NPM_PREFIX=$("$NPM_BIN" config get prefix) || [ -z "$NPM_PREFIX" ]; then
    echo "❌ Could not determine npm's global install prefix"
    exit 1
fi

# Install Claude Code globally
if command -v claude &>/dev/null; then
    echo "✅ Claude Code already installed ($(claude --version 2>/dev/null || echo 'version unknown'))"
    echo "💡 Update with: npm update -g @anthropic-ai/claude-code (use sudo only for a system-owned npm prefix)"
    exit 0
fi

echo "📦 Installing @anthropic-ai/claude-code..."
if [[ "$NPM_PREFIX" == "$HOME" || "$NPM_PREFIX" == "$HOME/"* ]] \
    || [ -w "$NPM_PREFIX" ] \
    || { [ ! -e "$NPM_PREFIX" ] && [ -w "$(dirname "$NPM_PREFIX")" ]; }; then
    "$NPM_BIN" install -g @anthropic-ai/claude-code
else
    sudo "$NPM_BIN" install -g @anthropic-ai/claude-code
fi

if command -v claude &>/dev/null; then
    echo "✅ Claude Code installed successfully!"
    echo ""
    echo "💡 Next step: run 'claude login' to authenticate in your browser"
else
    echo "❌ Installation failed or 'claude' is not in PATH"
    exit 1
fi
