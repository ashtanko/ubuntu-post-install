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
    curl -fsSL --retry 3 --retry-all-errors https://apt.releases.hashicorp.com/gpg \
        | sudo gpg --dearmor --yes -o /etc/apt/keyrings/hashicorp.gpg
    sudo chmod a+r /etc/apt/keyrings/hashicorp.gpg

    # HashiCorp ships an empty suite for some interim Ubuntu releases — 25.04
    # (plucky) serves an InRelease but carries no packages — so pick the newest
    # codename that actually publishes terraform, falling back to the LTSes.
    CODENAME=$(lsb_release -cs)
    HC_SUITE=""
    # Note: no `curl | grep -q` here — grep exits at the first match, curl dies
    # of SIGPIPE, and `set -o pipefail` would fail the check for every suite.
    HC_INDEX=$(mktemp)
    # shellcheck disable=SC2064
    trap "rm -f '$HC_INDEX'" EXIT
    for CANDIDATE in "$CODENAME" noble jammy; do
        if curl -fsSL --retry 3 --retry-all-errors -o "$HC_INDEX" \
            "https://apt.releases.hashicorp.com/dists/${CANDIDATE}/main/binary-${ARCH}/Packages" 2>/dev/null \
            && grep -q '^Package: terraform$' "$HC_INDEX"; then
            HC_SUITE="$CANDIDATE"
            break
        fi
    done
    rm -f "$HC_INDEX"
    if [ -z "$HC_SUITE" ]; then
        echo "❌ No HashiCorp apt suite publishes terraform for $CODENAME (${ARCH})"
        exit 1
    fi
    if [ "$HC_SUITE" != "$CODENAME" ]; then
        echo "⚠️  HashiCorp has no packages for $CODENAME — using the $HC_SUITE suite instead"
    fi

    echo "deb [arch=${ARCH} signed-by=/etc/apt/keyrings/hashicorp.gpg] \
https://apt.releases.hashicorp.com \
${HC_SUITE} main" \
        | sudo tee /etc/apt/sources.list.d/hashicorp.list > /dev/null

    echo "📦 Installing terraform..."
    sudo apt-get update
    sudo apt-get install -y terraform
    echo "✅ terraform installed ($(terraform version | head -1))"
fi

# --- tflint (GitHub release; checksum-verified zip) ---
# Deliberately not upstream's `curl .../master/install_linux.sh | sudo bash`:
# that pipes a mutable branch URL straight into root. Resolving the release tag
# and verifying the published digest matches how tools/just.sh, tools/yq.sh, and
# tools/lazydocker.sh install their binaries.
if command -v tflint &>/dev/null; then
    echo "✅ tflint already installed ($(tflint --version | head -1))"
else
    # The release ships a .zip, and unzip isn't on a stock Ubuntu install.
    if ! command -v unzip &>/dev/null; then
        echo "📦 Installing unzip (required to unpack the tflint release)..."
        sudo apt-get update
        sudo apt-get install -y unzip
    fi

    echo "🔍 Resolving latest tflint release..."
    TFLINT_VERSION=$(latest_github_tag terraform-linters/tflint)
    case "$ARCH" in
        amd64|arm64) TFLINT_ARCH="$ARCH" ;;
        *) echo "❌ Unsupported architecture for tflint: $ARCH"; exit 1 ;;
    esac
    TFLINT_ASSET="tflint_linux_${TFLINT_ARCH}.zip"
    TFLINT_BASE="https://github.com/terraform-linters/tflint/releases/download/${TFLINT_VERSION}"

    echo "📦 Downloading tflint $TFLINT_VERSION..."
    TMP_TFLINT=$(mktemp -d)
    trap 'rm -rf "$TMP_TFLINT"' EXIT
    wget --tries=3 --waitretry=2 -q --show-progress \
        -O "$TMP_TFLINT/$TFLINT_ASSET" "${TFLINT_BASE}/${TFLINT_ASSET}"

    echo "🔒 Verifying checksum..."
    curl -fsSL --retry 3 --retry-all-errors -o "$TMP_TFLINT/checksums.txt" "${TFLINT_BASE}/checksums.txt"
    EXPECTED_SHA=$(awk -v want="$TFLINT_ASSET" '$2 == want {print $1; exit}' "$TMP_TFLINT/checksums.txt")
    [[ "$EXPECTED_SHA" =~ ^[0-9a-fA-F]{64}$ ]] \
        || { echo "❌ tflint checksum manifest is missing a valid digest for $TFLINT_ASSET"; exit 1; }
    echo "$EXPECTED_SHA  $TMP_TFLINT/$TFLINT_ASSET" | sha256sum --check --quiet
    echo "✅ Checksum verified"

    unzip -q -o "$TMP_TFLINT/$TFLINT_ASSET" -d "$TMP_TFLINT"
    [ -f "$TMP_TFLINT/tflint" ] || { echo "❌ tflint binary not found in the release zip"; exit 1; }
    sudo install -m 0755 "$TMP_TFLINT/tflint" "$BIN_DIR/tflint"
    rm -rf "$TMP_TFLINT"
    echo "✅ tflint installed → $BIN_DIR/tflint ($(tflint --version | head -1))"
fi

# --- tfsec (GitHub release; single binary) ---
if command -v tfsec &>/dev/null; then
    echo "✅ tfsec already installed ($(tfsec --version))"
else
    echo "🔍 Resolving latest tfsec release..."
    TFSEC_VERSION=$(latest_github_tag aquasecurity/tfsec)
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
    wget --tries=3 --waitretry=2 -q --show-progress -O "$TMP" "$TFSEC_URL"
    sudo install -m 0755 "$TMP" "$BIN_DIR/tfsec"
    echo "✅ tfsec installed → $BIN_DIR/tfsec"
fi

echo ""
echo "✅ Terraform toolchain installed!"
echo "   terraform - core IaC engine"
echo "   tflint    - linter"
echo "   tfsec     - static security scanner"
