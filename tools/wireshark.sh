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

echo "🚀 Installing Wireshark..."

# $USER isn't reliably set outside a login shell.
CURRENT_USER="$(whoami)"

# Preseed the debconf question wireshark-common asks on install ("allow
# non-superusers to capture packets?") so apt never blocks on a prompt.
# Answering "true" grants dumpcap capabilities via the wireshark group —
# the same group system/user-groups.sh already adds this user to.
echo "wireshark-common wireshark-common/install-setuid boolean true" | sudo debconf-set-selections

if command -v wireshark &>/dev/null; then
    echo "✅ Wireshark already installed ($(wireshark --version 2>/dev/null | head -1))"
    echo "🔧 Re-affirming non-root capture permission..."
    sudo dpkg-reconfigure -f noninteractive wireshark-common
else
    echo "📦 Installing wireshark..."
    sudo apt-get update
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y wireshark
fi

# Belt-and-braces: grant capture rights even if system/user-groups.sh was
# never run, so this script is useful standalone.
if getent group wireshark >/dev/null 2>&1; then
    if groups "$CURRENT_USER" | grep -qw wireshark; then
        echo "✅ $CURRENT_USER already in the wireshark group"
    else
        echo "🔧 Adding $CURRENT_USER to the wireshark group..."
        sudo usermod -aG wireshark "$CURRENT_USER"
        echo "⚠️  Log out and back in (or run: newgrp wireshark) for capture permission to take effect"
    fi
else
    echo "⚠️  wireshark group not found — dumpcap will need sudo to capture"
fi

echo ""
echo "✅ Wireshark installed!"
echo "💡 GUI: wireshark   •   headless capture/analysis: tshark"
echo "💡 List capturable interfaces without sudo: tshark -D"
