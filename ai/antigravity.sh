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

echo "🚀 Installing Antigravity..."

if dpkg -l antigravity 2>/dev/null | grep -q "^ii"; then
    echo "✅ Antigravity already installed ($(antigravity --version 2>/dev/null || echo 'version unknown'))"
    exit 0
fi

echo "📦 Adding Antigravity GPG key and repository..."
sudo mkdir -p /etc/apt/keyrings

ANTIGRAVITY_KEY=$(mktemp)
trap 'rm -f "$ANTIGRAVITY_KEY"' EXIT
curl -fsSL --retry 3 --retry-all-errors -o "$ANTIGRAVITY_KEY" \
    https://us-central1-apt.pkg.dev/doc/repo-signing-key.gpg
sudo gpg --dearmor --yes -o /etc/apt/keyrings/antigravity-repo-key.gpg "$ANTIGRAVITY_KEY"
rm -f "$ANTIGRAVITY_KEY"
trap - EXIT

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
