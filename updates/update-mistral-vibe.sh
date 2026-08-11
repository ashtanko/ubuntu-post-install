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

VIBE_TOOL_DIR="$HOME/.local/share/uv/tools/mistral-vibe"
VIBE_BIN="$HOME/.local/bin/vibe"

if [ ! -d "$VIBE_TOOL_DIR" ] || [ ! -x "$VIBE_BIN" ]; then
    echo "⏭️  Skipping Mistral Vibe update: the repository-managed uv tool installation was not found."
    exit 0
fi
UV_BIN=$(command -v uv 2>/dev/null || true)
if [ -z "$UV_BIN" ] && [ -x "$HOME/.local/bin/uv" ]; then
    UV_BIN="$HOME/.local/bin/uv"
fi
if [ -z "$UV_BIN" ]; then
    echo "⏭️  Skipping Mistral Vibe update: uv is not installed."
    exit 0
fi

BEFORE_VERSION=$("$VIBE_BIN" --version 2>/dev/null || echo "version unknown")
echo "🚀 Updating Mistral Vibe..."
echo "   Before: $BEFORE_VERSION"
"$UV_BIN" tool upgrade mistral-vibe
AFTER_VERSION=$("$VIBE_BIN" --version 2>/dev/null || echo "version unknown")
echo "✅ Mistral Vibe update complete"
echo "   After:  $AFTER_VERSION"
