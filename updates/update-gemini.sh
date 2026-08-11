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

if ! GEMINI_BIN=$(command -v gemini); then
    echo "⏭️  Gemini CLI is not installed; skipping update."
    exit 0
fi

if ! command -v npm &>/dev/null; then
    echo "⏭️  The active Gemini installation cannot be verified without npm; skipping update."
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

GEMINI_PACKAGE_DIR="$NPM_ROOT/@google/gemini-cli"
EXPECTED_GEMINI_BIN="$NPM_PREFIX/bin/gemini"
if [ ! -d "$GEMINI_PACKAGE_DIR" ] || [ ! -e "$EXPECTED_GEMINI_BIN" ]; then
    echo "⏭️  Gemini CLI is not owned by the active npm global prefix; skipping update."
    exit 0
fi

if [ "$(readlink -f "$GEMINI_BIN")" != "$(readlink -f "$EXPECTED_GEMINI_BIN")" ]; then
    echo "⏭️  The active Gemini executable belongs to a different installation; skipping update."
    exit 0
fi

BEFORE_VERSION=$("$GEMINI_BIN" --version 2>/dev/null || echo "version unknown")
echo "🚀 Updating Gemini CLI..."
echo "   Before: $BEFORE_VERSION"

if [[ "$NPM_PREFIX" == "$HOME" || "$NPM_PREFIX" == "$HOME/"* ]] \
    || [ -w "$NPM_PREFIX" ] \
    || { [ ! -e "$NPM_PREFIX" ] && [ -w "$(dirname "$NPM_PREFIX")" ]; }; then
    "$NPM_BIN" install -g @google/gemini-cli@latest
else
    sudo "$NPM_BIN" install -g @google/gemini-cli@latest
fi

AFTER_VERSION=$("$EXPECTED_GEMINI_BIN" --version 2>/dev/null || echo "version unknown")
echo "✅ Gemini CLI update complete"
echo "   After:  $AFTER_VERSION"
