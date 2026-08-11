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

echo "🚀 Installing Bitwarden CLI..."

BIN_DIR="/usr/local/bin"

if command -v bw &>/dev/null; then
    echo "✅ Bitwarden CLI already installed ($(bw --version 2>/dev/null | head -1))"
    echo "💡 Update: re-run this script after removing $BIN_DIR/bw"
    exit 0
fi

echo "📦 Ensuring curl + unzip are present..."
sudo apt-get update
sudo apt-get install -y curl unzip

ARCH=$(dpkg --print-architecture)
if [ "$ARCH" != "amd64" ]; then
    # Bitwarden only publishes an x86_64 Linux CLI build.
    echo "❌ Bitwarden CLI has no official Linux build for architecture: $ARCH"
    exit 1
fi

echo "📦 Downloading Bitwarden CLI (official \"latest\" redirect)..."
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
curl -fL --progress-bar --retry 3 --retry-all-errors -o "$TMP/bw.zip" \
    "https://vault.bitwarden.com/download/?app=cli&platform=linux"

unzip -q -o "$TMP/bw.zip" -d "$TMP"
if [ ! -f "$TMP/bw" ]; then
    echo "❌ Downloaded archive does not contain a 'bw' binary"
    exit 1
fi

sudo install -m 0755 "$TMP/bw" "$BIN_DIR/bw"

if ! command -v bw &>/dev/null; then
    echo "❌ Bitwarden CLI installation failed or is not in PATH"
    exit 1
fi

echo ""
echo "✅ Bitwarden CLI installed ($(bw --version 2>/dev/null | head -1)) → $BIN_DIR/bw"
echo "💡 Log in:              bw login"
echo "💡 Unlock a session:    export BW_SESSION=\$(bw unlock --raw)"
echo "💡 Self-hosted vault?   bw config server https://your-instance.example.com"
