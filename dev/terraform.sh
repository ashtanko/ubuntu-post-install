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

# --- tflint (official installer; resolves arch + latest release) ---
if command -v tflint &>/dev/null; then
    echo "✅ tflint already installed ($(tflint --version | head -1))"
else
    # The installer unpacks a .zip, and unzip isn't on a stock Ubuntu install.
    if ! command -v unzip &>/dev/null; then
        echo "📦 Installing unzip (required by the tflint installer)..."
        sudo apt-get update
        sudo apt-get install -y unzip
    fi
    echo "📦 Installing tflint via official installer..."
    curl -fsSL --retry 3 --retry-all-errors https://raw.githubusercontent.com/terraform-linters/tflint/master/install_linux.sh | sudo bash
    echo "✅ tflint installed ($(tflint --version | head -1))"
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
    wget -q --show-progress -O "$TMP" "$TFSEC_URL"
    sudo install -m 0755 "$TMP" "$BIN_DIR/tfsec"
    echo "✅ tfsec installed → $BIN_DIR/tfsec"
fi

echo ""
echo "✅ Terraform toolchain installed!"
echo "   terraform - core IaC engine"
echo "   tflint    - linter"
echo "   tfsec     - static security scanner"
