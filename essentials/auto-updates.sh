#!/bin/bash
set -euo pipefail

# Re-exec under bash if invoked via `sh` (dash mishandles &>, [[ ]], etc.)
if [ -z "${BASH_VERSION:-}" ]; then
    exec /bin/bash "$0" "$@"
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ -f "$REPO_ROOT/.env" ]] && { set -a; source "$REPO_ROOT/.env"; set +a; }

echo "🚀 Configuring unattended security updates..."

if [[ "${ENABLE_AUTO_UPDATES:-yes}" == "no" ]]; then
    echo "⏭️  Skipping auto-updates (ENABLE_AUTO_UPDATES=no)"
    exit 0
fi

# Install unattended-upgrades if needed
if dpkg -s unattended-upgrades &>/dev/null; then
    echo "✅ unattended-upgrades already installed"
else
    echo "📦 Installing unattended-upgrades..."
    sudo apt update
    sudo apt install -y unattended-upgrades apt-listchanges
fi

# Enable daily Update + Unattended-Upgrade runs
AUTO_FILE="/etc/apt/apt.conf.d/20auto-upgrades"
DESIRED='APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";'

if [ -f "$AUTO_FILE" ] && printf '%s\n' "$DESIRED" | sudo cmp -s - "$AUTO_FILE"; then
    echo "✅ $AUTO_FILE already configured"
else
    echo "🔧 Writing $AUTO_FILE..."
    printf '%s\n' "$DESIRED" | sudo tee "$AUTO_FILE" > /dev/null
fi

echo "🔧 Ensuring service is enabled..."
sudo systemctl enable --now unattended-upgrades >/dev/null 2>&1 || true

echo ""
echo "✅ Auto-updates configured. Verify with:"
echo "     sudo unattended-upgrades --dry-run --debug | head -40"
