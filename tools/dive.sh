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

echo "🚀 Installing dive (Docker image layer explorer)..."

if command -v dive &>/dev/null; then
    echo "✅ dive already installed ($(dive --version 2>/dev/null | head -1))"
    exit 0
fi

# dive's .deb assets are named with the Debian arch names, so no translation
# table here (unlike the x86_64/aarch64 shape most Rust and Go releases use).
ARCH=$(dpkg --print-architecture)
case "$ARCH" in
    amd64|arm64) ;;
    *) echo "❌ Unsupported architecture: $ARCH"; exit 1 ;;
esac

echo "🔍 Resolving latest dive release..."
DIVE_VERSION=$(latest_github_tag wagoodman/dive)
DIVE_NUM=${DIVE_VERSION#v}
DIVE_ASSET="dive_${DIVE_NUM}_linux_${ARCH}.deb"
DIVE_BASE="https://github.com/wagoodman/dive/releases/download/${DIVE_VERSION}"

echo "📦 Downloading dive $DIVE_VERSION..."
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
wget --tries=3 --waitretry=2 -nv --show-progress -O "$TMP/$DIVE_ASSET" "${DIVE_BASE}/${DIVE_ASSET}"

echo "🔒 Verifying checksum..."
DIVE_CHECKSUMS="$TMP/checksums.txt"
curl -fsSL --retry 3 --retry-all-errors -o "$DIVE_CHECKSUMS" \
    "${DIVE_BASE}/dive_${DIVE_NUM}_checksums.txt"
EXPECTED_SHA=$(awk -v want="$DIVE_ASSET" '$2 == want {print $1; exit}' "$DIVE_CHECKSUMS")
[[ "$EXPECTED_SHA" =~ ^[0-9a-fA-F]{64}$ ]] \
    || { echo "❌ dive checksum manifest is missing a valid digest for $DIVE_ASSET"; exit 1; }
echo "$EXPECTED_SHA  $TMP/$DIVE_ASSET" | sha256sum --check --quiet
echo "✅ Checksum verified"

# A local .deb that's already on disk — no apt-get update needed to install it.
sudo apt-get install -y "$TMP/$DIVE_ASSET"

if ! command -v dive &>/dev/null; then
    echo "❌ dive installation failed or is not in PATH"
    exit 1
fi

echo ""
echo "✅ dive installed ($(dive --version 2>/dev/null | head -1))"
echo "💡 Explore an existing image layer by layer: dive <image>"
echo "💡 Build and analyse in one step: dive build -t <tag> ."
echo "💡 Fail CI on wasted space: CI=true dive --ci <image>"
echo "💡 Needs dev/docker.sh (or an existing Docker install) to be useful"
