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

echo "🚀 Installing just (command runner)..."

if command -v just &>/dev/null; then
    echo "✅ just already installed ($(just --version 2>/dev/null | head -1))"
    exit 0
fi

ARCH=$(dpkg --print-architecture)
case "$ARCH" in
    amd64) RUST_ARCH="x86_64"  ;;
    arm64) RUST_ARCH="aarch64" ;;
    *) echo "❌ Unsupported architecture: $ARCH"; exit 1 ;;
esac

BIN_DIR="/usr/local/bin"

echo "🔍 Resolving latest just release..."
# just's tags carry no `v` prefix (e.g. "1.58.0"), unlike most repos here.
JUST_VERSION=$(latest_github_tag casey/just)
JUST_ASSET="just-${JUST_VERSION}-${RUST_ARCH}-unknown-linux-musl.tar.gz"
JUST_BASE="https://github.com/casey/just/releases/download/${JUST_VERSION}"

echo "📦 Downloading just $JUST_VERSION..."
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
wget --tries=3 --waitretry=2 -nv --show-progress -O "$TMP/just.tar.gz" "${JUST_BASE}/${JUST_ASSET}"

echo "🔒 Verifying checksum..."
JUST_CHECKSUMS="$TMP/SHA256SUMS"
curl -fsSL --retry 3 --retry-all-errors -o "$JUST_CHECKSUMS" "${JUST_BASE}/SHA256SUMS"
EXPECTED_SHA=$(awk -v want="$JUST_ASSET" '$2 == want {print $1; exit}' "$JUST_CHECKSUMS")
[[ "$EXPECTED_SHA" =~ ^[0-9a-fA-F]{64}$ ]] \
    || { echo "❌ just checksum manifest is missing a valid digest for $JUST_ASSET"; exit 1; }
echo "$EXPECTED_SHA  $TMP/just.tar.gz" | sha256sum --check --quiet
echo "✅ Checksum verified"

tar -xzf "$TMP/just.tar.gz" -C "$TMP"
[ -f "$TMP/just" ] || { echo "❌ just binary not found in tarball"; exit 1; }
sudo install -m 0755 "$TMP/just" "$BIN_DIR/just"

if ! command -v just &>/dev/null; then
    echo "❌ just installation failed or is not in PATH"
    exit 1
fi

echo ""
echo "✅ just installed ($(just --version 2>/dev/null | head -1)) → $BIN_DIR/just"
echo "💡 Create a justfile, then run recipes by name: just build"
echo "💡 List available recipes: just --list"
