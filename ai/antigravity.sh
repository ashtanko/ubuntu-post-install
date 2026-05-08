#!/bin/bash
set -euo pipefail

# Re-exec under bash if invoked via `sh` (dash mishandles &>, [[ ]], etc.)
if [ -z "${BASH_VERSION:-}" ]; then
    exec /bin/bash "$0" "$@"
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ -f "$REPO_ROOT/.env" ]] && { set -a; source "$REPO_ROOT/.env"; set +a; }

echo "🚀 Installing Antigravity..."

if dpkg -l antigravity 2>/dev/null | grep -q "^ii"; then
    echo "✅ Antigravity already installed ($(antigravity --version 2>/dev/null || echo 'version unknown'))"
    exit 0
fi

echo "📦 Adding Antigravity GPG key and repository..."
sudo mkdir -p /etc/apt/keyrings

curl -fsSL https://us-central1-apt.pkg.dev/doc/repo-signing-key.gpg | \
    sudo gpg --dearmor --yes -o /etc/apt/keyrings/antigravity-repo-key.gpg

if [ ! -f /etc/apt/sources.list.d/antigravity.list ]; then
    echo "deb [signed-by=/etc/apt/keyrings/antigravity-repo-key.gpg] \
https://us-central1-apt.pkg.dev/projects/antigravity-auto-updater-dev/ antigravity-debian main" \
        | sudo tee /etc/apt/sources.list.d/antigravity.list > /dev/null
fi

echo "📦 Installing Antigravity..."
sudo apt update
sudo apt install -y antigravity

if dpkg -l antigravity 2>/dev/null | grep -q "^ii"; then
    echo "✅ Antigravity installed successfully!"
else
    echo "❌ Antigravity installation failed"
    exit 1
fi
