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

find_codex() {
    if [ -x "$HOME/.local/bin/codex" ]; then
        printf '%s\n' "$HOME/.local/bin/codex"
    else
        return 1
    fi
}

if ! CODEX_BIN=$(find_codex); then
    echo "⏭️  The standalone Codex CLI installed by this project was not found; skipping update."
    exit 0
fi

CODEX_RELEASE="${CODEX_RELEASE:-latest}"
if [ "$CODEX_RELEASE" != "latest" ]; then
    echo "⏭️  Codex is pinned to '$CODEX_RELEASE'; skipping the latest-release updater."
    exit 0
fi

if ! "$CODEX_BIN" update --help >/dev/null 2>&1; then
    echo "⏭️  This Codex version has no native update command; skipping update."
    exit 0
fi

BEFORE_VERSION=$("$CODEX_BIN" --version 2>/dev/null || echo "version unknown")
echo "🚀 Updating Codex CLI..."
echo "   Before: $BEFORE_VERSION"

"$CODEX_BIN" update

if ! CODEX_BIN=$(find_codex); then
    echo "❌ Codex CLI is no longer available after the update" >&2
    exit 1
fi

AFTER_VERSION=$("$CODEX_BIN" --version 2>/dev/null || echo "version unknown")
echo "✅ Codex CLI update complete"
echo "   After:  $AFTER_VERSION"
