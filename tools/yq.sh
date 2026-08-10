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

echo "🚀 Installing yq (YAML/JSON/XML processor)..."

# tools/cli-tools.sh installs jq for JSON; yq is the YAML counterpart, which
# this toolchain leans on constantly (Kubernetes manifests, pre-commit configs,
# GitHub Actions workflows, docker-compose files).
if command -v yq &>/dev/null; then
    echo "✅ yq already installed ($(yq --version 2>/dev/null | head -1))"
    exit 0
fi

ARCH=$(dpkg --print-architecture)
case "$ARCH" in
    amd64|arm64) ;;   # yq's asset names match dpkg's arch names
    *) echo "❌ Unsupported architecture: $ARCH"; exit 1 ;;
esac

BIN_DIR="/usr/local/bin"

echo "🔍 Resolving latest yq release..."
YQ_VERSION=$(latest_github_tag mikefarah/yq)
YQ_BINARY="yq_linux_${ARCH}"
YQ_ASSET="${YQ_BINARY}.tar.gz"
YQ_BASE="https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}"

echo "📦 Downloading yq $YQ_VERSION..."
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
wget --tries=3 --waitretry=2 -q --show-progress -O "$TMP/$YQ_ASSET" "${YQ_BASE}/${YQ_ASSET}"

# yq's `checksums` file is a matrix: column 1 is the filename, and the
# remaining columns are digests whose algorithm order is listed one-per-line
# in `checksums_hashes_order`. So SHA-256's awk field is its line number + 1.
echo "🔒 Verifying checksum..."
YQ_ORDER="$TMP/checksums_hashes_order"
YQ_CHECKSUMS="$TMP/checksums"
curl -fsSL --retry 3 --retry-all-errors -o "$YQ_ORDER" "${YQ_BASE}/checksums_hashes_order"
curl -fsSL --retry 3 --retry-all-errors -o "$YQ_CHECKSUMS" "${YQ_BASE}/checksums"

SHA_LINE=$(grep -n '^SHA-256$' "$YQ_ORDER" | cut -d: -f1)
[[ "$SHA_LINE" =~ ^[0-9]+$ ]] \
    || { echo "❌ Could not locate SHA-256 in yq's checksum algorithm order"; exit 1; }
EXPECTED_SHA=$(awk -v want="$YQ_ASSET" -v col="$((SHA_LINE + 1))" '$1 == want {print $col; exit}' "$YQ_CHECKSUMS")
[[ "$EXPECTED_SHA" =~ ^[0-9a-fA-F]{64}$ ]] \
    || { echo "❌ yq checksum manifest is missing a valid digest for $YQ_ASSET"; exit 1; }
echo "$EXPECTED_SHA  $TMP/$YQ_ASSET" | sha256sum --check --quiet
echo "✅ Checksum verified"

tar -xzf "$TMP/$YQ_ASSET" -C "$TMP"
[ -f "$TMP/$YQ_BINARY" ] || { echo "❌ $YQ_BINARY not found in tarball"; exit 1; }
sudo install -m 0755 "$TMP/$YQ_BINARY" "$BIN_DIR/yq"

if ! command -v yq &>/dev/null; then
    echo "❌ yq installation failed or is not in PATH"
    exit 1
fi

echo ""
echo "✅ yq installed ($(yq --version 2>/dev/null | head -1)) → $BIN_DIR/yq"
echo "💡 Read a value:   yq '.services.web.image' docker-compose.yml"
echo "💡 YAML → JSON:    yq -o=json '.' config.yml"
echo "💡 Edit in place:  yq -i '.version = \"2\"' config.yml"
