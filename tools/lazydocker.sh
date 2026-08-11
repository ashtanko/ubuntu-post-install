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

echo "🚀 Installing lazydocker (terminal UI for Docker)..."

if command -v lazydocker &>/dev/null; then
    echo "✅ lazydocker already installed ($(lazydocker --version 2>/dev/null | head -1))"
    exit 0
fi

ARCH=$(dpkg --print-architecture)
case "$ARCH" in
    amd64) LD_ARCH="x86_64" ;;
    arm64) LD_ARCH="arm64" ;;
    *) echo "❌ Unsupported architecture: $ARCH"; exit 1 ;;
esac

BIN_DIR="/usr/local/bin"

echo "🔍 Resolving latest lazydocker release..."
LD_VERSION=$(latest_github_tag jesseduffield/lazydocker)
LD_NUM=${LD_VERSION#v}
LD_ASSET="lazydocker_${LD_NUM}_Linux_${LD_ARCH}.tar.gz"
LD_URL="https://github.com/jesseduffield/lazydocker/releases/download/${LD_VERSION}/${LD_ASSET}"

echo "📦 Downloading lazydocker $LD_VERSION..."
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
wget --tries=3 --waitretry=2 -nv --show-progress -O "$TMP/lazydocker.tar.gz" "$LD_URL"

echo "🔒 Verifying checksum..."
LD_CHECKSUMS="$TMP/checksums.txt"
curl -fsSL --retry 3 --retry-all-errors -o "$LD_CHECKSUMS" \
    "https://github.com/jesseduffield/lazydocker/releases/download/${LD_VERSION}/checksums.txt"
EXPECTED_SHA=$(awk -v want="$LD_ASSET" '$2 == want {print $1; exit}' "$LD_CHECKSUMS")
[[ "$EXPECTED_SHA" =~ ^[0-9a-fA-F]{64}$ ]] \
    || { echo "❌ lazydocker checksum manifest is missing a valid digest for $LD_ASSET"; exit 1; }
echo "$EXPECTED_SHA  $TMP/lazydocker.tar.gz" | sha256sum --check --quiet
echo "✅ Checksum verified"

tar -xzf "$TMP/lazydocker.tar.gz" -C "$TMP"
sudo install -m 0755 "$TMP/lazydocker" "$BIN_DIR/lazydocker"

if ! command -v lazydocker &>/dev/null; then
    echo "❌ lazydocker installation failed or is not in PATH"
    exit 1
fi

echo ""
echo "✅ lazydocker installed ($LD_VERSION) → $BIN_DIR/lazydocker"
echo "💡 Run 'lazydocker' inside any directory with a docker/compose context"
echo "💡 Needs dev/docker.sh (or an existing Docker install) to be useful"
