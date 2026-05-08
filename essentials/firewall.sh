#!/bin/bash
set -euo pipefail

# Re-exec under bash if invoked via `sh` (dash mishandles &>, [[ ]], etc.)
if [ -z "${BASH_VERSION:-}" ]; then
    exec /bin/bash "$0" "$@"
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ -f "$REPO_ROOT/.env" ]] && { set -a; source "$REPO_ROOT/.env"; set +a; }

echo "🚀 Configuring UFW firewall..."

if [[ "${ENABLE_UFW:-yes}" == "no" ]]; then
    echo "⏭️  Skipping UFW (ENABLE_UFW=no)"
    exit 0
fi

# Install UFW if needed
if ! command -v ufw &>/dev/null; then
    echo "📦 Installing ufw..."
    sudo apt update
    sudo apt install -y ufw
else
    echo "✅ ufw already installed"
fi

# Apply safe defaults: deny incoming, allow outgoing
echo "🔧 Setting default policies (deny in / allow out)..."
sudo ufw default deny incoming  > /dev/null
sudo ufw default allow outgoing > /dev/null

# Allow SSH so you don't lock yourself out of a remote box; rate-limit brute-force
echo "🔧 Allowing + rate-limiting OpenSSH..."
sudo ufw limit OpenSSH > /dev/null || sudo ufw limit 22/tcp > /dev/null

# Enable (idempotent)
if sudo ufw status | grep -q "Status: active"; then
    echo "✅ UFW already active"
else
    echo "y" | sudo ufw enable > /dev/null
    echo "✅ UFW enabled"
fi

echo ""
sudo ufw status verbose
