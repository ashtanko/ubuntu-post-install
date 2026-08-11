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

ATUIN_BIN=""
for CANDIDATE in "$HOME/.atuin/bin/atuin" "$HOME/.local/bin/atuin"; do
    if [ -n "$CANDIDATE" ] && [ -x "$CANDIDATE" ]; then
        ATUIN_BIN="$CANDIDATE"
        break
    fi
done

if [ -z "$ATUIN_BIN" ]; then
    echo "⏭️  Skipping Atuin update: no user-local Atuin installation was found."
    exit 0
fi

BEFORE_VERSION=$("$ATUIN_BIN" --version 2>/dev/null | head -1 || true)
echo "🚀 Updating Atuin (${BEFORE_VERSION:-version unknown})..."
"$ATUIN_BIN" update
AFTER_VERSION=$("$ATUIN_BIN" --version 2>/dev/null | head -1 || true)
echo "✅ Atuin updated: ${BEFORE_VERSION:-unknown} → ${AFTER_VERSION:-unknown}"
