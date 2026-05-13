#!/bin/bash
set -euo pipefail

# Re-exec under bash if invoked via `sh` (dash mishandles &>, [[ ]], etc.)
if [ -z "${BASH_VERSION:-}" ]; then
    exec /bin/bash "$0" "$@"
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ -f "$REPO_ROOT/.env" ]] && { set -a; source "$REPO_ROOT/.env"; set +a; }

echo "🚀 Installing Kubernetes toolchain (kubectl, helm, k9s, kind, kustomize)..."

ARCH=$(dpkg --print-architecture)   # amd64 | arm64
case "$ARCH" in
    amd64) GO_ARCH="amd64"; UNAME_ARCH="x86_64" ;;
    arm64) GO_ARCH="arm64"; UNAME_ARCH="arm64"  ;;
    *) echo "❌ Unsupported architecture: $ARCH"; exit 1 ;;
esac

BIN_DIR="/usr/local/bin"

# --- kubectl (Kubernetes apt repo) ---
if command -v kubectl &>/dev/null; then
    echo "✅ kubectl already installed ($(kubectl version --client --output=yaml 2>/dev/null | grep gitVersion | head -1 | awk '{print $2}'))"
else
    echo "📦 Adding Kubernetes apt repository..."
    sudo apt-get update
    sudo apt-get install -y ca-certificates curl gnupg

    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.31/deb/Release.key \
        | sudo gpg --dearmor --yes -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
    sudo chmod a+r /etc/apt/keyrings/kubernetes-apt-keyring.gpg

    echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] \
https://pkgs.k8s.io/core:/stable:/v1.31/deb/ /" \
        | sudo tee /etc/apt/sources.list.d/kubernetes.list > /dev/null

    echo "📦 Installing kubectl..."
    sudo apt-get update
    sudo apt-get install -y kubectl
    echo "✅ kubectl installed"
fi

# --- helm (official apt repo) ---
if command -v helm &>/dev/null; then
    echo "✅ helm already installed ($(helm version --short 2>/dev/null))"
else
    echo "📦 Adding Helm apt repository..."
    curl -fsSL https://baltocdn.com/helm/signing.asc \
        | sudo gpg --dearmor --yes -o /etc/apt/keyrings/helm.gpg
    sudo chmod a+r /etc/apt/keyrings/helm.gpg

    echo "deb [arch=${ARCH} signed-by=/etc/apt/keyrings/helm.gpg] \
https://baltocdn.com/helm/stable/debian/ all main" \
        | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list > /dev/null

    echo "📦 Installing helm..."
    sudo apt-get update
    sudo apt-get install -y helm
    echo "✅ helm installed"
fi

# --- k9s (GitHub release) ---
if command -v k9s &>/dev/null; then
    echo "✅ k9s already installed ($(k9s version --short 2>/dev/null | head -1))"
else
    echo "🔍 Resolving latest k9s release..."
    K9S_VERSION=$(curl -fsSL https://api.github.com/repos/derailed/k9s/releases/latest \
        | grep '"tag_name"' | cut -d'"' -f4)
    K9S_URL="https://github.com/derailed/k9s/releases/download/${K9S_VERSION}/k9s_Linux_${GO_ARCH}.tar.gz"
    echo "📦 Downloading k9s $K9S_VERSION..."
    TMP=$(mktemp -d)
    trap 'rm -rf "$TMP"' EXIT
    wget -q --show-progress -O "$TMP/k9s.tar.gz" "$K9S_URL"
    tar -xzf "$TMP/k9s.tar.gz" -C "$TMP"
    sudo install -m 0755 "$TMP/k9s" "$BIN_DIR/k9s"
    echo "✅ k9s installed → $BIN_DIR/k9s"
fi

# --- kind (GitHub release; single binary) ---
if command -v kind &>/dev/null; then
    echo "✅ kind already installed ($(kind version 2>/dev/null))"
else
    echo "🔍 Resolving latest kind release..."
    KIND_VERSION=$(curl -fsSL https://api.github.com/repos/kubernetes-sigs/kind/releases/latest \
        | grep '"tag_name"' | cut -d'"' -f4)
    KIND_URL="https://kind.sigs.k8s.io/dl/${KIND_VERSION}/kind-linux-${GO_ARCH}"
    echo "📦 Downloading kind $KIND_VERSION..."
    TMP_KIND=$(mktemp)
    # shellcheck disable=SC2064
    trap "rm -f '$TMP_KIND'" EXIT
    wget -q --show-progress -O "$TMP_KIND" "$KIND_URL"
    sudo install -m 0755 "$TMP_KIND" "$BIN_DIR/kind"
    echo "✅ kind installed → $BIN_DIR/kind"
fi

# --- kustomize (official installer script — picks correct arch) ---
if command -v kustomize &>/dev/null; then
    echo "✅ kustomize already installed ($(kustomize version 2>/dev/null))"
else
    echo "📦 Installing kustomize..."
    TMP_KUST=$(mktemp -d)
    # shellcheck disable=SC2064
    trap "rm -rf '$TMP_KUST'" EXIT
    (cd "$TMP_KUST" && curl -fsSL https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh | bash)
    sudo install -m 0755 "$TMP_KUST/kustomize" "$BIN_DIR/kustomize"
    echo "✅ kustomize installed → $BIN_DIR/kustomize"
fi

# Silence unused-variable warning when the arch isn't needed for any branch above
: "$UNAME_ARCH"

echo ""
echo "✅ Kubernetes toolchain installed!"
echo "   kubectl    - Kubernetes CLI"
echo "   helm       - package manager"
echo "   k9s        - terminal UI"
echo "   kind       - local clusters via Docker"
echo "   kustomize  - YAML patch tool"
echo "💡 Spin up a local cluster: kind create cluster"
