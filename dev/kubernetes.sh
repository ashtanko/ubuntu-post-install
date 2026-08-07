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

# Resolve the newest release tag of a GitHub repo without calling api.github.com —
# unauthenticated API calls are rate-limited per IP and start returning 403 in CI.
# Follows the /releases/latest redirect and reads the tag back out of the URL.
latest_github_tag() {
    local repo="$1" url
    url=$(curl -fsSLI --retry 3 --retry-all-errors -o /dev/null -w '%{url_effective}' "https://github.com/${repo}/releases/latest")
    case "$url" in
        */releases/tag/*) printf '%s\n' "${url##*/releases/tag/}" ;;
        *) echo "❌ Could not resolve latest release for $repo" >&2; return 1 ;;
    esac
}

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

# --- helm (official tarball from get.helm.sh) ---
# The apt repo at baltocdn.com is not resolvable from every network (CI runners
# included), so pull the release tarball straight from Helm's own CDN instead.
if command -v helm &>/dev/null; then
    echo "✅ helm already installed ($(helm version --short 2>/dev/null))"
else
    echo "🔍 Resolving latest helm release..."
    HELM_VERSION=$(curl -fsSL --retry 3 --retry-all-errors https://get.helm.sh/helm-latest-version)
    echo "📦 Downloading helm $HELM_VERSION..."
    TMP_HELM=$(mktemp -d)
    # shellcheck disable=SC2064
    trap "rm -rf '$TMP_HELM'" EXIT
    curl -fsSL --retry 3 --retry-all-errors -o "$TMP_HELM/helm.tar.gz" \
        "https://get.helm.sh/helm-${HELM_VERSION}-linux-${GO_ARCH}.tar.gz"
    tar -xzf "$TMP_HELM/helm.tar.gz" -C "$TMP_HELM" --strip-components=1
    sudo install -m 0755 "$TMP_HELM/helm" "$BIN_DIR/helm"
    echo "✅ helm installed → $BIN_DIR/helm"
fi

# --- k9s (GitHub release) ---
if command -v k9s &>/dev/null; then
    echo "✅ k9s already installed ($(k9s version --short 2>/dev/null | head -1))"
else
    echo "🔍 Resolving latest k9s release..."
    K9S_VERSION=$(latest_github_tag derailed/k9s)
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
    KIND_VERSION=$(latest_github_tag kubernetes-sigs/kind)
    KIND_URL="https://kind.sigs.k8s.io/dl/${KIND_VERSION}/kind-linux-${GO_ARCH}"
    echo "📦 Downloading kind $KIND_VERSION..."
    TMP_KIND=$(mktemp)
    # shellcheck disable=SC2064
    trap "rm -f '$TMP_KIND'" EXIT
    wget -q --show-progress -O "$TMP_KIND" "$KIND_URL"
    sudo install -m 0755 "$TMP_KIND" "$BIN_DIR/kind"
    echo "✅ kind installed → $BIN_DIR/kind"
fi

# --- kustomize (GitHub release; tags are prefixed `kustomize/`) ---
if command -v kustomize &>/dev/null; then
    echo "✅ kustomize already installed ($(kustomize version 2>/dev/null))"
else
    echo "🔍 Resolving latest kustomize release..."
    KUST_TAG=$(latest_github_tag kubernetes-sigs/kustomize)   # e.g. kustomize/v5.8.1
    KUST_VERSION="${KUST_TAG##*/}"                            # e.g. v5.8.1
    # The `/` in the tag has to stay percent-encoded in the download URL.
    KUST_URL="https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2F${KUST_VERSION}/kustomize_${KUST_VERSION}_linux_${GO_ARCH}.tar.gz"
    echo "📦 Downloading kustomize $KUST_VERSION..."
    TMP_KUST=$(mktemp -d)
    # shellcheck disable=SC2064
    trap "rm -rf '$TMP_KUST'" EXIT
    curl -fsSL --retry 3 --retry-all-errors -o "$TMP_KUST/kustomize.tar.gz" "$KUST_URL"
    tar -xzf "$TMP_KUST/kustomize.tar.gz" -C "$TMP_KUST"
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
