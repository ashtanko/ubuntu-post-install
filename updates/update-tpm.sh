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

TPM_DIR="${TMUX_PLUGIN_DIR:-$HOME/.tmux/plugins/tpm}"
if [ ! -d "$TPM_DIR/.git" ]; then
    echo "⏭️  Skipping TPM update: the repository-managed checkout was not found at $TPM_DIR."
    exit 0
fi
TPM_REMOTE=$(git -C "$TPM_DIR" config --get remote.origin.url 2>/dev/null || true)
case "$TPM_REMOTE" in
    https://github.com/tmux-plugins/tpm|https://github.com/tmux-plugins/tpm.git) ;;
    *)
        echo "⏭️  Skipping TPM update: the checkout does not use the official upstream remote."
        exit 0
        ;;
esac
if [ -n "$(git -C "$TPM_DIR" status --porcelain)" ]; then
    echo "❌ Refusing to update TPM: the Git checkout at $TPM_DIR has uncommitted changes." >&2
    exit 1
fi

BEFORE_COMMIT=$(git -C "$TPM_DIR" rev-parse --short HEAD)
echo "🚀 Updating TPM..."
echo "   Before: $BEFORE_COMMIT"
git -C "$TPM_DIR" pull --ff-only
AFTER_COMMIT=$(git -C "$TPM_DIR" rev-parse --short HEAD)
echo "✅ TPM update complete"
echo "   After:  $AFTER_COMMIT"
