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

echo "🚀 Installing Google Cloud CLI..."

if command -v gcloud &>/dev/null; then
    echo "✅ gcloud already installed ($(gcloud --version 2>/dev/null | head -1))"
else
    echo "📦 Adding Google Cloud apt repository..."
    sudo apt-get update
    sudo apt-get install -y apt-transport-https ca-certificates gnupg curl

    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL --retry 3 --retry-all-errors https://packages.cloud.google.com/apt/doc/apt-key.gpg \
        | sudo gpg --dearmor --yes -o /etc/apt/keyrings/google-cloud.gpg
    sudo chmod a+r /etc/apt/keyrings/google-cloud.gpg

    echo "deb [signed-by=/etc/apt/keyrings/google-cloud.gpg] https://packages.cloud.google.com/apt cloud-sdk main" \
        | sudo tee /etc/apt/sources.list.d/google-cloud-sdk.list > /dev/null

    echo "📦 Installing google-cloud-cli..."
    sudo apt-get update
    sudo apt-get install -y google-cloud-cli
    echo "✅ gcloud installed ($(gcloud --version 2>/dev/null | head -1))"
fi

# gke-gcloud-auth-plugin is what makes `kubectl` able to auth against GKE
# clusters — natural pairing with dev/kubernetes.sh.
if command -v gke-gcloud-auth-plugin &>/dev/null; then
    echo "✅ gke-gcloud-auth-plugin already installed"
else
    echo "📦 Installing gke-gcloud-auth-plugin (for kubectl + GKE)..."
    sudo apt-get install -y google-cloud-cli-gke-gcloud-auth-plugin
fi

echo ""
echo "✅ Google Cloud CLI ready!"
echo "💡 Authenticate:        gcloud auth login"
echo "💡 Set a project:       gcloud config set project <project-id>"
echo "💡 kubectl for GKE:     gcloud container clusters get-credentials <cluster> --zone <zone>"
