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

ZSH="${ZSH:-$HOME/.oh-my-zsh}"
UPGRADE_SCRIPT="$ZSH/tools/upgrade.sh"
if ! command -v zsh &>/dev/null || [ ! -d "$ZSH/.git" ] || [ ! -f "$UPGRADE_SCRIPT" ]; then
    echo "⏭️  Skipping Oh My Zsh update: Oh My Zsh is not installed."
    exit 0
fi
ZSH_REMOTE=$(git -C "$ZSH" config --get remote.origin.url 2>/dev/null || true)
case "$ZSH_REMOTE" in
    https://github.com/ohmyzsh/ohmyzsh|https://github.com/ohmyzsh/ohmyzsh.git) ;;
    *)
        echo "⏭️  Skipping Oh My Zsh update: the checkout does not use the official upstream remote."
        exit 0
        ;;
esac
if [ -n "$(git -C "$ZSH" status --porcelain)" ]; then
    echo "❌ Refusing to update Oh My Zsh: the checkout at $ZSH has uncommitted changes." >&2
    exit 1
fi

BEFORE_VERSION=$(git -C "$ZSH" rev-parse --short HEAD 2>/dev/null || true)
echo "🚀 Updating Oh My Zsh (${BEFORE_VERSION:-version unknown})..."
zsh "$UPGRADE_SCRIPT" -v silent
AFTER_VERSION=$(git -C "$ZSH" rev-parse --short HEAD 2>/dev/null || true)
echo "✅ Oh My Zsh updated: ${BEFORE_VERSION:-unknown} → ${AFTER_VERSION:-unknown}"
