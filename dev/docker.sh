#!/bin/bash
set -euo pipefail

# Re-exec under bash if invoked via `sh` (dash mishandles &>, [[ ]], etc.)
if [ -z "${BASH_VERSION:-}" ]; then
    exec /bin/bash "$0" "$@"
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ -f "$REPO_ROOT/.env" ]] && { set -a; source "$REPO_ROOT/.env"; set +a; }

echo "🚀 Installing Docker Engine and Docker Desktop..."

ARCH=$(dpkg --print-architecture)
USERNAME="${USER:-$(id -un)}"

# --- Docker Engine ---
if command -v docker &>/dev/null; then
    echo "✅ Docker Engine already installed ($(docker --version))"
else
    echo "📦 Adding Docker GPG key and repository..."
    sudo apt-get update
    sudo apt-get install -y ca-certificates curl gnupg lsb-release

    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
        | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    sudo chmod a+r /etc/apt/keyrings/docker.gpg

    echo "deb [arch=${ARCH} signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu \
$(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
        | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    echo "📦 Installing Docker Engine..."
    sudo apt-get update
    sudo apt-get install -y \
        docker-ce docker-ce-cli containerd.io \
        docker-buildx-plugin docker-compose-plugin

    echo "✅ Docker Engine installed ($(docker --version))"
fi

# Add current user to docker group
if groups "$USERNAME" | grep -q docker; then
    echo "✅ User already in docker group"
else
    echo "👤 Adding $USERNAME to docker group..."
    sudo usermod -aG docker "$USERNAME"
    echo "⚠️  Log out and back in (or run: newgrp docker) for group membership to take effect"
fi

# --- Docker Desktop ---
if [[ "${INSTALL_DOCKER_DESKTOP:-yes}" == "no" ]]; then
    echo "⏭️  Skipping Docker Desktop (INSTALL_DOCKER_DESKTOP=no)"
elif dpkg -s docker-desktop &>/dev/null 2>&1; then
    echo "✅ Docker Desktop already installed"
else
    echo "📦 Downloading Docker Desktop..."
    DEB=$(mktemp --suffix=.deb)
    trap 'rm -f "$DEB"' EXIT

    wget -q --show-progress \
        -O "$DEB" \
        "https://desktop.docker.com/linux/main/${ARCH}/docker-desktop-${ARCH}.deb"

    echo "🛠️  Installing Docker Desktop..."
    sudo apt-get install -y "$DEB"
    echo "✅ Docker Desktop installed"
fi  # end INSTALL_DOCKER_DESKTOP

echo ""
echo "✅ Docker setup complete!"
echo "💡 Start Docker Desktop: systemctl --user start docker-desktop"
