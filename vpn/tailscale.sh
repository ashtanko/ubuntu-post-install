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

echo "🚀 Installing Tailscale..."

if command -v tailscale &>/dev/null; then
    echo "✅ Tailscale already installed ($(tailscale version 2>/dev/null | head -1))"
else
    echo "📦 Ensuring curl is present..."
    sudo apt-get update
    sudo apt-get install -y curl

    echo "📦 Downloading and running the official Tailscale installer..."
    # Execute from a completed file so retries can't duplicate streamed input,
    # while leaving stdin attached to the terminal for apt's prompts.
    TS_INSTALLER=$(mktemp)
    trap 'rm -f "$TS_INSTALLER"' EXIT
    curl -fsSL --retry 3 --retry-all-errors -o "$TS_INSTALLER" https://tailscale.com/install.sh
    sh "$TS_INSTALLER"
    rm -f "$TS_INSTALLER"
    trap - EXIT

    if ! command -v tailscale &>/dev/null; then
        echo "❌ Tailscale installation failed or 'tailscale' is not in PATH"
        exit 1
    fi
    echo "✅ Tailscale installed ($(tailscale version 2>/dev/null | head -1))"
fi

# The installer's apt package brings in and enables the tailscaled systemd
# service; only meaningful where systemd is actually PID 1.
if [ -d /run/systemd/system ] && command -v systemctl &>/dev/null; then
    if systemctl is-active --quiet tailscaled 2>/dev/null; then
        echo "✅ tailscaled is running"
    else
        echo "🔧 Starting tailscaled..."
        sudo systemctl enable --now tailscaled
    fi
else
    echo "⚠️  No systemd — tailscaled won't run here; verify on real hardware"
fi

echo ""
if [ -n "${TAILSCALE_AUTHKEY:-}" ]; then
    echo "🔑 TAILSCALE_AUTHKEY is set — authenticating non-interactively..."
    sudo tailscale up --authkey="$TAILSCALE_AUTHKEY"
    echo "✅ Connected: $(tailscale ip -4 2>/dev/null || echo 'pending')"
else
    echo "✅ Tailscale setup complete!"
    echo "💡 Next step: run 'sudo tailscale up' and follow the browser login prompt."
    echo "💡 Or set TAILSCALE_AUTHKEY in .env to authenticate non-interactively next run."
fi
