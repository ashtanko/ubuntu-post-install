#!/bin/bash
set -euo pipefail

# Re-exec under bash if invoked via `sh` (dash mishandles &>, [[ ]], etc.)
if [ -z "${BASH_VERSION:-}" ]; then
    exec /bin/bash "$0" "$@"
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ -f "$REPO_ROOT/.env" ]] && { set -a; source "$REPO_ROOT/.env"; set +a; }

echo "🚀 Installing Terraform + tflint + tfsec..."

ARCH=$(dpkg --print-architecture)
BIN_DIR="/usr/local/bin"

# --- Terraform (HashiCorp apt repo) ---
if command -v terraform &>/dev/null; then
    echo "✅ terraform already installed ($(terraform version | head -1))"
else
    echo "📦 Adding HashiCorp apt repository..."
    sudo apt-get update
    sudo apt-get install -y ca-certificates curl gnupg lsb-release

    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://apt.releases.hashicorp.com/gpg \
        | sudo gpg --dearmor --yes -o /etc/apt/keyrings/hashicorp.gpg
    sudo chmod a+r /etc/apt/keyrings/hashicorp.gpg

    echo "deb [arch=${ARCH} signed-by=/etc/apt/keyrings/hashicorp.gpg] \
https://apt.releases.hashicorp.com \
$(lsb_release -cs) main" \
        | sudo tee /etc/apt/sources.list.d/hashicorp.list > /dev/null

    echo "📦 Installing terraform..."
    sudo apt-get update
    sudo apt-get install -y terraform
    echo "✅ terraform installed ($(terraform version | head -1))"
fi

# --- tflint (official installer; resolves arch + latest release) ---
if command -v tflint &>/dev/null; then
    echo "✅ tflint already installed ($(tflint --version | head -1))"
else
    echo "📦 Installing tflint via official installer..."
    curl -fsSL https://raw.githubusercontent.com/terraform-linters/tflint/master/install_linux.sh | sudo bash
    echo "✅ tflint installed ($(tflint --version | head -1))"
fi

# --- tfsec (GitHub release; single binary) ---
if command -v tfsec &>/dev/null; then
    echo "✅ tfsec already installed ($(tfsec --version))"
else
    echo "🔍 Resolving latest tfsec release..."
    TFSEC_VERSION=$(curl -fsSL https://api.github.com/repos/aquasecurity/tfsec/releases/latest \
        | grep '"tag_name"' | cut -d'"' -f4)
    case "$ARCH" in
        amd64) TFSEC_ARCH="amd64" ;;
        arm64) TFSEC_ARCH="arm64" ;;
        *) echo "❌ Unsupported architecture for tfsec: $ARCH"; exit 1 ;;
    esac
    TFSEC_URL="https://github.com/aquasecurity/tfsec/releases/download/${TFSEC_VERSION}/tfsec-linux-${TFSEC_ARCH}"
    echo "📦 Downloading tfsec $TFSEC_VERSION..."
    TMP=$(mktemp)
    # shellcheck disable=SC2064
    trap "rm -f '$TMP'" EXIT
    wget -q --show-progress -O "$TMP" "$TFSEC_URL"
    sudo install -m 0755 "$TMP" "$BIN_DIR/tfsec"
    echo "✅ tfsec installed → $BIN_DIR/tfsec"
fi

echo ""
echo "✅ Terraform toolchain installed!"
echo "   terraform - core IaC engine"
echo "   tflint    - linter"
echo "   tfsec     - static security scanner"
