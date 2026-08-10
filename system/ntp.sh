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

echo "🚀 Ensuring the system clock is time-synced..."

# Detect whether systemd is the active init (timedatectl needs it).
HAVE_SYSTEMD=0
[ -d /run/systemd/system ] && HAVE_SYSTEMD=1

if [ "$HAVE_SYSTEMD" = "1" ]; then
    if [ "$(timedatectl show -p NTP --value 2>/dev/null)" = "yes" ]; then
        echo "✅ NTP already enabled"
    else
        echo "🔧 Enabling NTP time sync (systemd-timesyncd)..."
        sudo timedatectl set-ntp true
        echo "✅ NTP enabled"
    fi
else
    if ! command -v chronyd &>/dev/null; then
        echo "📦 Installing chrony..."
        sudo apt update
        sudo apt install -y chrony
    else
        echo "✅ chrony already installed"
    fi

    # No systemd here (container, WSL1, ...) — nothing to enable/start via
    # systemctl. Whatever init the host actually uses is responsible for
    # bringing chronyd up.
    echo "💡 No systemd detected — chrony is installed but service management is left to your init system"
fi

echo ""
if [ "$HAVE_SYSTEMD" = "1" ]; then
    timedatectl | sed 's/^/   /'
else
    chronyc tracking 2>/dev/null | sed 's/^/   /' || true
fi
