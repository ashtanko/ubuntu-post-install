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

echo "🚀 Configuring swap..."

SWAP_FILE="${SWAP_FILE:-/swapfile}"
FSTAB_FILE="${FSTAB_FILE:-/etc/fstab}"
SWAP_SIZE_GB="${SWAP_SIZE_GB:-4}"

# Skip if any swap is already active (file or partition)
if [ "$(swapon --show --noheadings 2>/dev/null | wc -l)" -gt 0 ]; then
    echo "✅ Swap already active:"
    swapon --show
    exit 0
fi

if [ -f "$SWAP_FILE" ]; then
    echo "⚠️  $SWAP_FILE exists but is not active — enabling it"
    sudo swapon "$SWAP_FILE"
else
    echo "📦 Creating ${SWAP_SIZE_GB}G swap file at $SWAP_FILE..."
    sudo fallocate -l "${SWAP_SIZE_GB}G" "$SWAP_FILE"
    sudo chmod 600 "$SWAP_FILE"
    sudo mkswap "$SWAP_FILE"
    sudo swapon "$SWAP_FILE"
fi

# Persist across reboots
if ! awk -v swap_file="$SWAP_FILE" \
    '$1 == swap_file && $2 == "none" && $3 == "swap" { found = 1 } END { exit !found }' \
    "$FSTAB_FILE"; then
    echo "${SWAP_FILE} none swap sw 0 0" | sudo tee -a "$FSTAB_FILE" > /dev/null
    echo "✅ Added $SWAP_FILE to $FSTAB_FILE"
fi

echo ""
echo "✅ Swap is active:"
swapon --show
echo "💡 Tune swappiness with: echo 'vm.swappiness=10' | sudo tee /etc/sysctl.d/99-swappiness.conf"
