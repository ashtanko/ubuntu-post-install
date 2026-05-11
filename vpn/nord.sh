#!/bin/bash
set -euo pipefail

# Re-exec under bash if invoked via `sh` (dash mishandles &>, [[ ]], etc.)
if [ -z "${BASH_VERSION:-}" ]; then
    exec /bin/bash "$0" "$@"
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ -f "$REPO_ROOT/.env" ]] && { set -a; source "$REPO_ROOT/.env"; set +a; }

echo "🚀 Installing NordVPN..."

USERNAME="${USER:-$(id -un)}"

if command -v nordvpn >/dev/null 2>&1; then
    echo "✅ NordVPN already installed ($(nordvpn --version 2>/dev/null | head -1))"
else
    echo "📦 Ensuring curl is present..."
    sudo apt-get install -y curl

    echo "📦 Downloading and running official NordVPN installer..."
    # Process substitution (not `curl | sh`) so apt's "Y/n" prompt can read
    # from the terminal — piping makes stdin the closed curl pipe and apt
    # sees EOF and aborts. Matches the form in NordVPN's official docs.
    sh <(curl -sSf https://downloads.nordcdn.com/apps/linux/install.sh)

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
