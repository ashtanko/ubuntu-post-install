#!/bin/bash
set -euo pipefail

if [ -z "${BASH_VERSION:-}" ]; then
    exec /bin/bash "$0" "$@"
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_HELPER="$REPO_ROOT/lib/config.bash"
# shellcheck source=lib/config.bash
source "$CONFIG_HELPER" || { echo "❌ Missing config helper: $CONFIG_HELPER" >&2; exit 1; }
load_config "$REPO_ROOT"

echo "🚀 Installing MCP Inspector..."

MCP_INSPECTOR_VERSION="${MCP_INSPECTOR_VERSION:-latest}"

if command -v mcp-inspector &>/dev/null; then
    echo "✅ MCP Inspector already installed"
    exit 0
fi

NODE_BIN=""
NPM_BIN=""
if command -v node &>/dev/null && command -v npm &>/dev/null; then
    NODE_VERSION=$(node -v | sed 's/^v//')
    if [ "$(printf '%s\n' 22.19.0 "$NODE_VERSION" | sort -V | head -n1)" = "22.19.0" ]; then
        NODE_BIN=$(command -v node)
        NPM_BIN=$(command -v npm)
    fi
fi

if [ -z "$NODE_BIN" ]; then
    echo "📦 Installing Node.js 22 via the signed NodeSource repository..."
    NODE_KEY=$(mktemp --suffix=.gpg)
    trap 'rm -f "$NODE_KEY"' EXIT
    sudo apt-get update
    sudo apt-get install -y curl gpg ca-certificates
    curl -fsSL --retry 3 --retry-all-errors \
        https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
        | gpg --dearmor > "$NODE_KEY"
    sudo install -D -o root -g root -m 644 "$NODE_KEY" /etc/apt/keyrings/nodesource.gpg
    echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_22.x nodistro main" \
        | sudo tee /etc/apt/sources.list.d/nodesource.list >/dev/null
    sudo apt-get update
    sudo apt-get install -y nodejs
    rm -f "$NODE_KEY"
    trap - EXIT
    NODE_BIN=/usr/bin/node
    NPM_BIN=/usr/bin/npm
fi

if [ ! -x "$NODE_BIN" ] || [ ! -x "$NPM_BIN" ]; then
    echo "❌ Node.js 22.19+ and npm are required for MCP Inspector" >&2
    exit 1
fi

NODE_VERSION=$("$NODE_BIN" -v | sed 's/^v//')
if [ "$(printf '%s\n' 22.19.0 "$NODE_VERSION" | sort -V | head -n1)" != "22.19.0" ]; then
    echo "❌ MCP Inspector requires Node.js 22.19+, found v$NODE_VERSION" >&2
    exit 1
fi

if ! NPM_PREFIX=$(PATH="$(dirname "$NODE_BIN"):$PATH" "$NPM_BIN" config get prefix) \
    || [ -z "$NPM_PREFIX" ]; then
    echo "❌ Could not determine npm's global install prefix" >&2
    exit 1
fi
INSPECTOR_PACKAGE="@modelcontextprotocol/inspector@$MCP_INSPECTOR_VERSION"
echo "📦 Installing $INSPECTOR_PACKAGE..."
if [[ "$NPM_PREFIX" == "$HOME" || "$NPM_PREFIX" == "$HOME/"* ]] \
    || [ -w "$NPM_PREFIX" ] \
    || { [ ! -e "$NPM_PREFIX" ] && [ -w "$(dirname "$NPM_PREFIX")" ]; }; then
    PATH="$(dirname "$NODE_BIN"):$PATH" "$NPM_BIN" install -g "$INSPECTOR_PACKAGE"
else
    sudo env PATH="$(dirname "$NODE_BIN"):/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
        "$NPM_BIN" install -g "$INSPECTOR_PACKAGE"
fi

if ! command -v mcp-inspector &>/dev/null; then
    echo "❌ MCP Inspector installation failed or 'mcp-inspector' is not in PATH" >&2
    exit 1
fi

echo "✅ MCP Inspector installed successfully"
echo "💡 Run 'mcp-inspector <server-command>' to inspect a local MCP server"
