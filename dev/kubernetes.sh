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
GITHUB_HELPER="$REPO_ROOT/lib/github.bash"
# shellcheck source=lib/github.bash
source "$GITHUB_HELPER" || { echo "❌ Missing github helper: $GITHUB_HELPER" >&2; exit 1; }

echo "🚀 Installing Kubernetes toolchain (kubectl, helm, k9s, kind, kustomize)..."

ARCH=$(dpkg --print-architecture)   # amd64 | arm64
case "$ARCH" in
    amd64) GO_ARCH="amd64" ;;
    arm64) GO_ARCH="arm64" ;;
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
    curl -fsSL --retry 3 --retry-all-errors https://pkgs.k8s.io/core:/stable:/v1.31/deb/Release.key \
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
    HELM_TARBALL="helm-${HELM_VERSION}-linux-${GO_ARCH}.tar.gz"
    echo "📦 Downloading helm $HELM_VERSION..."
    TMP_HELM=$(mktemp -d)
    # shellcheck disable=SC2064
    trap "rm -rf '$TMP_HELM'" EXIT
    curl -fsSL --retry 3 --retry-all-errors -o "$TMP_HELM/helm.tar.gz" \
        "https://get.helm.sh/${HELM_TARBALL}"

    echo "🔒 Verifying checksum..."
    HELM_CHECKSUMS="$TMP_HELM/helm.sha256sum"
    curl -fsSL --retry 3 --retry-all-errors -o "$HELM_CHECKSUMS" \
        "https://get.helm.sh/${HELM_TARBALL}.sha256sum"
    EXPECTED_SHA=$(awk 'NR==1 {print $1}' "$HELM_CHECKSUMS")
    [[ "$EXPECTED_SHA" =~ ^[0-9a-fA-F]{64}$ ]] \
        || { echo "❌ Helm checksum manifest is missing a valid digest for $HELM_TARBALL"; exit 1; }
    echo "$EXPECTED_SHA  $TMP_HELM/helm.tar.gz" | sha256sum --check --quiet
    echo "✅ Checksum verified"

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
    K9S_ASSET="k9s_Linux_${GO_ARCH}.tar.gz"
    K9S_URL="https://github.com/derailed/k9s/releases/download/${K9S_VERSION}/${K9S_ASSET}"
    echo "📦 Downloading k9s $K9S_VERSION..."
    TMP=$(mktemp -d)
    trap 'rm -rf "$TMP"' EXIT
    wget --tries=3 --waitretry=2 -q --show-progress -O "$TMP/k9s.tar.gz" "$K9S_URL"

    echo "🔒 Verifying checksum..."
    K9S_CHECKSUMS="$TMP/checksums.sha256"
    curl -fsSL --retry 3 --retry-all-errors -o "$K9S_CHECKSUMS" \
        "https://github.com/derailed/k9s/releases/download/${K9S_VERSION}/checksums.sha256"
    EXPECTED_SHA=$(awk -v want="$K9S_ASSET" '$2 == want {print $1; exit}' "$K9S_CHECKSUMS")
    [[ "$EXPECTED_SHA" =~ ^[0-9a-fA-F]{64}$ ]] \
        || { echo "❌ k9s checksum manifest is missing a valid digest for $K9S_ASSET"; exit 1; }
    echo "$EXPECTED_SHA  $TMP/k9s.tar.gz" | sha256sum --check --quiet
    echo "✅ Checksum verified"

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
    KIND_CHECKSUMS="${TMP_KIND}.sha256sum"
    # shellcheck disable=SC2064
    trap "rm -f '$TMP_KIND' '$KIND_CHECKSUMS'" EXIT
    wget --tries=3 --waitretry=2 -q --show-progress -O "$TMP_KIND" "$KIND_URL"

    echo "🔒 Verifying checksum..."
    curl -fsSL --retry 3 --retry-all-errors -o "$KIND_CHECKSUMS" "${KIND_URL}.sha256sum"
    EXPECTED_SHA=$(awk 'NR==1 {print $1}' "$KIND_CHECKSUMS")
    [[ "$EXPECTED_SHA" =~ ^[0-9a-fA-F]{64}$ ]] \
        || { echo "❌ kind checksum manifest is missing a valid digest for kind-linux-$GO_ARCH"; exit 1; }
    echo "$EXPECTED_SHA  $TMP_KIND" | sha256sum --check --quiet
    echo "✅ Checksum verified"

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
    KUST_ASSET="kustomize_${KUST_VERSION}_linux_${GO_ARCH}.tar.gz"
    # The `/` in the tag has to stay percent-encoded in the download URL.
    KUST_RELEASE_BASE="https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2F${KUST_VERSION}"
    KUST_URL="${KUST_RELEASE_BASE}/${KUST_ASSET}"
    echo "📦 Downloading kustomize $KUST_VERSION..."
    TMP_KUST=$(mktemp -d)
    # shellcheck disable=SC2064
    trap "rm -rf '$TMP_KUST'" EXIT
    curl -fsSL --retry 3 --retry-all-errors -o "$TMP_KUST/kustomize.tar.gz" "$KUST_URL"

    echo "🔒 Verifying checksum..."
    KUST_CHECKSUMS="$TMP_KUST/checksums.txt"
    curl -fsSL --retry 3 --retry-all-errors -o "$KUST_CHECKSUMS" \
        "${KUST_RELEASE_BASE}/checksums.txt"
    EXPECTED_SHA=$(awk -v want="$KUST_ASSET" '$2 == want {print $1; exit}' "$KUST_CHECKSUMS")
    [[ "$EXPECTED_SHA" =~ ^[0-9a-fA-F]{64}$ ]] \
        || { echo "❌ kustomize checksum manifest is missing a valid digest for $KUST_ASSET"; exit 1; }
    echo "$EXPECTED_SHA  $TMP_KUST/kustomize.tar.gz" | sha256sum --check --quiet
    echo "✅ Checksum verified"

    tar -xzf "$TMP_KUST/kustomize.tar.gz" -C "$TMP_KUST"
    sudo install -m 0755 "$TMP_KUST/kustomize" "$BIN_DIR/kustomize"
    echo "✅ kustomize installed → $BIN_DIR/kustomize"
fi

echo ""
echo "✅ Kubernetes toolchain installed!"
echo "   kubectl    - Kubernetes CLI"
echo "   helm       - package manager"
echo "   k9s        - terminal UI"
echo "   kind       - local clusters via Docker"
echo "   kustomize  - YAML patch tool"
echo "💡 Spin up a local cluster: kind create cluster"
