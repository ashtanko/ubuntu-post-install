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

NVIM_INSTALL_DIR="${NVIM_INSTALL_DIR:-$HOME/.local/share/nvim-stable}"
NVIM_MANAGED_BIN="$NVIM_INSTALL_DIR/bin/nvim"
NVIM_LINK="$HOME/.local/bin/nvim"

if [ ! -x "$NVIM_MANAGED_BIN" ] || [ ! -e "$NVIM_LINK" ] \
    || [ "$(readlink -f "$NVIM_LINK")" != "$(readlink -f "$NVIM_MANAGED_BIN")" ]; then
    echo "⏭️  Skipping Neovim update: the repository-managed installation was not found at $NVIM_INSTALL_DIR."
    exit 0
fi
if [ -n "${NVIM_VERSION:-}" ]; then
    echo "⏭️  Skipping Neovim update: NVIM_VERSION is pinned to '$NVIM_VERSION'."
    exit 0
fi
if [ -n "${NVIM_ARCHIVE_URL:-}" ]; then
    echo "⏭️  Skipping Neovim update: a custom archive URL is configured."
    exit 0
fi

BEFORE_VERSION=$("$NVIM_MANAGED_BIN" --version 2>/dev/null | head -1 || true)
echo "🚀 Updating Neovim..."
echo "   Before: ${BEFORE_VERSION:-version unknown}"

UPI_NVIM_UPDATE=1 /bin/bash "$REPO_ROOT/ide/nvim.sh"

if [ ! -x "$NVIM_MANAGED_BIN" ]; then
    echo "❌ Neovim is no longer available after the update" >&2
    exit 1
fi
AFTER_VERSION=$("$NVIM_MANAGED_BIN" --version 2>/dev/null | head -1 || true)
echo "✅ Neovim update complete"
echo "   After:  ${AFTER_VERSION:-version unknown}"
