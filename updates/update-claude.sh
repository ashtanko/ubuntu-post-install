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

if ! CLAUDE_BIN=$(command -v claude); then
    echo "⏭️  Claude Code is not installed; skipping update."
    exit 0
fi

if ! dpkg-query -W -f='${Status}' claude-code 2>/dev/null | grep -q 'ok installed'; then
    echo "⏭️  Claude Code is not managed by the APT package installed by this project; skipping update."
    exit 0
fi

if ! dpkg-query -S "$CLAUDE_BIN" 2>/dev/null | grep -q '^claude-code:'; then
    echo "⏭️  The active Claude executable is not owned by the claude-code APT package; skipping update."
    exit 0
fi

BEFORE_VERSION=$("$CLAUDE_BIN" --version 2>/dev/null || echo "version unknown")
echo "🚀 Updating Claude Code..."
echo "   Before: $BEFORE_VERSION"

sudo apt-get update
sudo apt-get install -y --only-upgrade claude-code

AFTER_VERSION=$("$CLAUDE_BIN" --version 2>/dev/null || echo "version unknown")
echo "✅ Claude Code update complete"
echo "   After:  $AFTER_VERSION"
