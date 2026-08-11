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

echo "🚀 Installing Azure CLI..."

if command -v az &>/dev/null; then
    echo "✅ Azure CLI already installed ($(az version --output tsv 2>/dev/null | head -1))"
    exit 0
fi

echo "📦 Ensuring curl is present..."
sudo apt-get update
sudo apt-get install -y curl

# Microsoft's own installer handles key/repo/codename compatibility for us —
# same reasoning as vpn/nord.sh and vpn/tailscale.sh for their vendor scripts.
echo "📦 Downloading and running the official Azure CLI installer..."
AZ_INSTALLER=$(mktemp)
trap 'rm -f "$AZ_INSTALLER"' EXIT
curl -fsSL --retry 3 --retry-all-errors -o "$AZ_INSTALLER" https://aka.ms/InstallAzureCLIDeb
sudo bash "$AZ_INSTALLER"
rm -f "$AZ_INSTALLER"
trap - EXIT

if ! command -v az &>/dev/null; then
    echo "❌ Azure CLI installation failed or 'az' is not in PATH"
    exit 1
fi

echo ""
echo "✅ Azure CLI installed ($(az version --output tsv 2>/dev/null | head -1))"
echo "💡 Authenticate:  az login"
echo "💡 Set a subscription: az account set --subscription <name-or-id>"
echo "💡 kubectl for AKS:    az aks get-credentials --resource-group <rg> --name <cluster>"
