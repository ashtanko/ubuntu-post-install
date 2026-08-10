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

echo "🚀 Enabling periodic SSD/NVMe TRIM..."

if ! command -v fstrim &>/dev/null; then
    echo "📦 Installing util-linux (provides fstrim)..."
    sudo apt update
    sudo apt install -y util-linux
fi

# fstrim.timer runs `fstrim --all`, which already skips filesystems that
# don't support discard — but on a box with only spinning disks, enabling it
# is pure no-op churn, so check for a non-rotational block device first.
if ! lsblk -dn -o ROTA 2>/dev/null | grep -qw '0'; then
    echo "⏭️  No SSD/NVMe detected (all disks rotational) — fstrim isn't useful here, skipping"
    exit 0
fi

if [ ! -d /run/systemd/system ]; then
    echo "⏭️  systemd not present — fstrim.timer can't be managed here; run \`sudo fstrim -av\` manually/via cron instead"
    exit 0
fi

if systemctl is-enabled --quiet fstrim.timer 2>/dev/null; then
    echo "✅ fstrim.timer already enabled"
else
    echo "🔧 Enabling fstrim.timer (weekly TRIM)..."
    sudo systemctl enable --now fstrim.timer >/dev/null
    echo "✅ fstrim.timer enabled"
fi

echo ""
systemctl status fstrim.timer --no-pager -l 2>/dev/null | sed 's/^/   /' || true
