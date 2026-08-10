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

echo "🚀 Installing NordVPN..."

USERNAME="${USER:-$(id -un)}"

if command -v nordvpn >/dev/null 2>&1; then
    echo "✅ NordVPN already installed ($(nordvpn --version 2>/dev/null | head -1))"
else
    echo "📦 Ensuring curl is present..."
    sudo apt-get update
    sudo apt-get install -y curl

    echo "📦 Downloading and running official NordVPN installer..."
    # Execute from a completed file so retries cannot duplicate streamed input,
    # while leaving stdin attached to the terminal for apt's "Y/n" prompt.
    NORD_INSTALLER=$(mktemp)
    trap 'rm -f "$NORD_INSTALLER"' EXIT
    curl -sSf --retry 3 --retry-all-errors -o "$NORD_INSTALLER" \
        https://downloads.nordcdn.com/apps/linux/install.sh
    sh "$NORD_INSTALLER"
    rm -f "$NORD_INSTALLER"
    trap - EXIT

    if ! command -v nordvpn >/dev/null 2>&1; then
        echo "❌ NordVPN installation failed or 'nordvpn' is not in PATH"
        exit 1
    fi
    echo "✅ NordVPN installed ($(nordvpn --version 2>/dev/null | head -1))"
fi

# Add current user to nordvpn group (needed for non-root CLI access)
if getent group nordvpn >/dev/null 2>&1; then
    if groups "$USERNAME" | grep -qw nordvpn; then
        echo "✅ User already in nordvpn group"
    else
        echo "👤 Adding $USERNAME to nordvpn group..."
        sudo usermod -aG nordvpn "$USERNAME"
        echo "⚠️  Log out and back in (or run: newgrp nordvpn) for group membership to take effect"
    fi
else
    echo "⚠️  nordvpn group does not exist — installer may have changed; check 'getent group nordvpn'"
fi

echo ""
echo "✅ NordVPN setup complete!"
echo "💡 Next step: run 'nordvpn login' and follow the browser prompt."
echo "💡 Then try: nordvpn connect"
