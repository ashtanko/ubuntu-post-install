#!/bin/bash
set -euo pipefail

# Re-exec under bash if invoked via `sh` (dash mishandles &>, [[ ]], etc.)
if [ -z "${BASH_VERSION:-}" ]; then
    exec /bin/bash "$0" "$@"
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ -f "$REPO_ROOT/.env" ]] && { set -a; source "$REPO_ROOT/.env"; set +a; }

echo "🚀 Setting up keyboard remapping with keyd..."

KEYD_CONF="/etc/keyd/default.conf"

# Install keyd if needed
if ! command -v keyd &>/dev/null; then
    echo "📦 Installing keyd..."
    sudo apt update
    sudo apt install -y keyd
else
    echo "✅ keyd already installed"
fi

# Expected config content
read -r -d '' KEYD_CONFIG <<'EOF' || true
[ids]
*

[main]
# Left Alt → Left Ctrl (macOS-style)
leftalt = leftcontrol

# Left Ctrl → Meta (Cmd key)
leftcontrol = leftmeta
EOF

# Only write if config doesn't already match
sudo mkdir -p /etc/keyd
CONFIG_CHANGED=0
if [ -f "$KEYD_CONF" ] && printf '%s\n' "$KEYD_CONFIG" | sudo cmp -s - "$KEYD_CONF"; then
    echo "✅ keyd config already up to date"
else
    echo "⌨️  Writing keyd config (macOS-style: Left Alt → Ctrl, Left Ctrl → Meta)..."
    printf '%s\n' "$KEYD_CONFIG" | sudo tee "$KEYD_CONF" > /dev/null
    CONFIG_CHANGED=1
fi

# Enable service (idempotent) and only restart when config changed
echo "🔧 Enabling keyd service..."
sudo systemctl enable keyd >/dev/null 2>&1 || true

if [ "$CONFIG_CHANGED" -eq 1 ] || ! systemctl is-active --quiet keyd; then
    echo "🔄 Restarting keyd service..."
    sudo systemctl restart keyd
fi

# Verify
if systemctl is-active --quiet keyd; then
    echo "✅ keyd is running"
else
    echo "❌ keyd failed to start"
    exit 1
fi
