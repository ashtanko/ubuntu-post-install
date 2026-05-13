#!/bin/bash
set -euo pipefail

# Re-exec under bash if invoked via `sh` (dash mishandles &>, [[ ]], etc.)
if [ -z "${BASH_VERSION:-}" ]; then
    exec /bin/bash "$0" "$@"
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ -f "$REPO_ROOT/.env" ]] && { set -a; source "$REPO_ROOT/.env"; set +a; }

echo "🚀 Installing AWS CLI v2 + Session Manager plugin..."

ARCH=$(dpkg --print-architecture)
case "$ARCH" in
    amd64) AWS_ARCH="x86_64"; SSM_ARCH="64bit"   ;;
    arm64) AWS_ARCH="aarch64"; SSM_ARCH="arm64"  ;;
    *) echo "❌ Unsupported architecture: $ARCH"; exit 1 ;;
esac

# --- AWS CLI v2 (official zip installer) ---
if command -v aws &>/dev/null; then
    echo "✅ aws already installed ($(aws --version 2>&1))"
else
    sudo apt-get update
    sudo apt-get install -y unzip curl

    echo "📦 Downloading AWS CLI v2 ($AWS_ARCH)..."
    TMP=$(mktemp -d)
    trap 'rm -rf "$TMP"' EXIT
    AWS_ZIP_URL="https://awscli.amazonaws.com/awscli-exe-linux-${AWS_ARCH}.zip"
    wget -q --show-progress -O "$TMP/awscliv2.zip" "$AWS_ZIP_URL"
    unzip -q "$TMP/awscliv2.zip" -d "$TMP"
    sudo "$TMP/aws/install" --update
    echo "✅ aws installed ($(aws --version 2>&1))"
fi

# --- Session Manager plugin (.deb from Amazon S3) ---
if command -v session-manager-plugin &>/dev/null; then
    echo "✅ session-manager-plugin already installed"
else
    echo "📦 Downloading session-manager-plugin ($SSM_ARCH)..."
    DEB=$(mktemp --suffix=.deb)
    # shellcheck disable=SC2064
    trap "rm -f '$DEB'" EXIT
    SSM_URL="https://s3.amazonaws.com/session-manager-downloads/plugin/latest/ubuntu_${SSM_ARCH}/session-manager-plugin.deb"
    wget -q --show-progress -O "$DEB" "$SSM_URL"
    sudo apt-get install -y "$DEB"
    echo "✅ session-manager-plugin installed"
fi

echo ""
echo "✅ AWS toolchain ready!"
echo "💡 Configure credentials: aws configure"
echo "💡 Start an SSM session:  aws ssm start-session --target i-xxxxxxxxxxxx"
