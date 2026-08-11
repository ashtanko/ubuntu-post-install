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

COMPOSER_BIN="/usr/local/bin/composer"
ACTIVE_COMPOSER="$(command -v composer 2>/dev/null || true)"
if [ ! -x "$COMPOSER_BIN" ]; then
    echo "⏭️  Skipping Composer update: the repository-managed standalone PHAR was not found at $COMPOSER_BIN."
    exit 0
fi

if [ -z "$ACTIVE_COMPOSER" ] || [ "$(readlink -f "$ACTIVE_COMPOSER")" != "$COMPOSER_BIN" ]; then
    echo "⏭️  Skipping Composer update: $COMPOSER_BIN is not the active Composer installation."
    exit 0
fi

if dpkg-query -S "$COMPOSER_BIN" &>/dev/null; then
    echo "⏭️  Skipping Composer update: $COMPOSER_BIN is owned by a Debian package."
    exit 0
fi

BEFORE_VERSION=$("$COMPOSER_BIN" --version 2>/dev/null | head -1 || true)
echo "🚀 Updating Composer (${BEFORE_VERSION:-version unknown})..."
if [ -w "$COMPOSER_BIN" ]; then
    "$COMPOSER_BIN" self-update --no-interaction
else
    sudo "$COMPOSER_BIN" self-update --no-interaction
fi
AFTER_VERSION=$("$COMPOSER_BIN" --version 2>/dev/null | head -1 || true)
echo "✅ Composer updated: ${BEFORE_VERSION:-unknown} → ${AFTER_VERSION:-unknown}"
