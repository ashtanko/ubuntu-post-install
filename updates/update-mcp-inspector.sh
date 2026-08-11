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

MCP_INSPECTOR_VERSION="${MCP_INSPECTOR_VERSION:-latest}"
if [ "$MCP_INSPECTOR_VERSION" != "latest" ]; then
    echo "⏭️  MCP Inspector is pinned to '$MCP_INSPECTOR_VERSION'; skipping the latest-version updater."
    exit 0
fi

if ! INSPECTOR_BIN=$(command -v mcp-inspector); then
    echo "⏭️  MCP Inspector is not installed; skipping update."
    exit 0
fi

if ! command -v npm &>/dev/null; then
    echo "⏭️  The active MCP Inspector installation cannot be verified without npm; skipping update."
    exit 0
fi

NPM_BIN=$(type -P npm)
if [[ "$NPM_BIN" != /* ]]; then
    NPM_BIN="$(cd "$(dirname "$NPM_BIN")" && pwd)/${NPM_BIN##*/}"
fi
if ! NPM_PREFIX=$("$NPM_BIN" config get prefix) || [ -z "$NPM_PREFIX" ]; then
    echo "❌ Could not determine npm's global install prefix" >&2
    exit 1
fi
if ! NPM_ROOT=$("$NPM_BIN" root -g) || [ -z "$NPM_ROOT" ]; then
    echo "❌ Could not determine npm's global package root" >&2
    exit 1
fi

INSPECTOR_PACKAGE_DIR="$NPM_ROOT/@modelcontextprotocol/inspector"
EXPECTED_INSPECTOR_BIN="$NPM_PREFIX/bin/mcp-inspector"
if [ ! -d "$INSPECTOR_PACKAGE_DIR" ] || [ ! -e "$EXPECTED_INSPECTOR_BIN" ]; then
    echo "⏭️  MCP Inspector is not owned by the active npm global prefix; skipping update."
    exit 0
fi

if [ "$(readlink -f "$INSPECTOR_BIN")" != "$(readlink -f "$EXPECTED_INSPECTOR_BIN")" ]; then
    echo "⏭️  The active MCP Inspector executable belongs to a different installation; skipping update."
    exit 0
fi

BEFORE_VERSION=$("$INSPECTOR_BIN" --version 2>/dev/null || echo "version unknown")
echo "🚀 Updating MCP Inspector..."
echo "   Before: $BEFORE_VERSION"

if [[ "$NPM_PREFIX" == "$HOME" || "$NPM_PREFIX" == "$HOME/"* ]] \
    || [ -w "$NPM_PREFIX" ] \
    || { [ ! -e "$NPM_PREFIX" ] && [ -w "$(dirname "$NPM_PREFIX")" ]; }; then
    "$NPM_BIN" install -g @modelcontextprotocol/inspector@latest
else
    sudo "$NPM_BIN" install -g @modelcontextprotocol/inspector@latest
fi

AFTER_VERSION=$("$EXPECTED_INSPECTOR_BIN" --version 2>/dev/null || echo "version unknown")
echo "✅ MCP Inspector update complete"
echo "   After:  $AFTER_VERSION"
