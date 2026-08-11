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

CLAUDE_PACKAGE="@anthropic-ai/claude-code"

if ! CLAUDE_BIN=$(command -v claude); then
    echo "⏭️  Claude Code is not installed; skipping update."
    exit 0
fi

# Claude Code ships both as Anthropic's APT package (what ai/claude.sh
# installs) and as a global npm package. Update whichever one actually owns
# the executable on PATH, and never guess: an unowned binary is left alone.
if dpkg-query -W -f='${Status}' claude-code 2>/dev/null | grep -q 'ok installed' \
    && dpkg-query -S "$CLAUDE_BIN" 2>/dev/null | grep -q '^claude-code:'; then
    BEFORE_VERSION=$("$CLAUDE_BIN" --version 2>/dev/null || echo "version unknown")
    echo "🚀 Updating Claude Code (APT package)..."
    echo "   Before: $BEFORE_VERSION"

    sudo apt-get update
    sudo apt-get install -y --only-upgrade claude-code

    AFTER_VERSION=$("$CLAUDE_BIN" --version 2>/dev/null || echo "version unknown")
    echo "✅ Claude Code update complete"
    echo "   After:  $AFTER_VERSION"
    exit 0
fi

if ! command -v npm &>/dev/null; then
    echo "⏭️  Claude Code is not managed by the APT package installed by this project, and the installation cannot be verified without npm; skipping update."
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

CLAUDE_PACKAGE_DIR="$NPM_ROOT/$CLAUDE_PACKAGE"
EXPECTED_CLAUDE_BIN="$NPM_PREFIX/bin/claude"
if [ ! -d "$CLAUDE_PACKAGE_DIR" ] || [ ! -e "$EXPECTED_CLAUDE_BIN" ]; then
    echo "⏭️  Claude Code is owned by neither the claude-code APT package nor the active npm global prefix; skipping update."
    exit 0
fi

if [ "$(readlink -f "$CLAUDE_BIN")" != "$(readlink -f "$EXPECTED_CLAUDE_BIN")" ]; then
    echo "⏭️  The active Claude executable belongs to a different installation; skipping update."
    exit 0
fi

# The npm package publishes both channels as dist-tags, so the same knob that
# selects ai/claude.sh's APT channel selects the npm release here.
CLAUDE_CHANNEL="${CLAUDE_CHANNEL:-stable}"
case "$CLAUDE_CHANNEL" in
    stable|latest) ;;
    *)
        echo "❌ Unsupported CLAUDE_CHANNEL: $CLAUDE_CHANNEL (expected stable or latest)" >&2
        exit 2
        ;;
esac

BEFORE_VERSION=$("$CLAUDE_BIN" --version 2>/dev/null || echo "version unknown")
echo "🚀 Updating Claude Code (npm global, ${CLAUDE_CHANNEL} channel)..."
echo "   Before: $BEFORE_VERSION"

if [[ "$NPM_PREFIX" == "$HOME" || "$NPM_PREFIX" == "$HOME/"* ]] \
    || [ -w "$NPM_PREFIX" ] \
    || { [ ! -e "$NPM_PREFIX" ] && [ -w "$(dirname "$NPM_PREFIX")" ]; }; then
    "$NPM_BIN" install -g "${CLAUDE_PACKAGE}@${CLAUDE_CHANNEL}"
else
    sudo "$NPM_BIN" install -g "${CLAUDE_PACKAGE}@${CLAUDE_CHANNEL}"
fi

AFTER_VERSION=$("$EXPECTED_CLAUDE_BIN" --version 2>/dev/null || echo "version unknown")
echo "✅ Claude Code update complete"
echo "   After:  $AFTER_VERSION"
