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

echo "🚀 Installing ctop (container metrics TUI)..."

if command -v ctop &>/dev/null; then
    echo "✅ ctop already installed ($(ctop -v 2>/dev/null | head -1))"
    exit 0
fi

# ctop's release assets use the Debian arch names, so no translation table.
ARCH=$(dpkg --print-architecture)
case "$ARCH" in
    amd64|arm64) ;;
    *) echo "❌ Unsupported architecture: $ARCH"; exit 1 ;;
esac

BIN_DIR="/usr/local/bin"

echo "🔍 Resolving latest ctop release..."
CTOP_VERSION=$(latest_github_tag bcicen/ctop)
CTOP_NUM=${CTOP_VERSION#v}
CTOP_ASSET="ctop-${CTOP_NUM}-linux-${ARCH}"
CTOP_BASE="https://github.com/bcicen/ctop/releases/download/${CTOP_VERSION}"

echo "📦 Downloading ctop $CTOP_VERSION..."
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
wget --tries=3 --waitretry=2 -nv --show-progress -O "$TMP/ctop" "${CTOP_BASE}/${CTOP_ASSET}"

echo "🔒 Verifying checksum..."
CTOP_CHECKSUMS="$TMP/sha256sums.txt"
curl -fsSL --retry 3 --retry-all-errors -o "$CTOP_CHECKSUMS" "${CTOP_BASE}/sha256sums.txt"
EXPECTED_SHA=$(awk -v want="$CTOP_ASSET" '$2 == want {print $1; exit}' "$CTOP_CHECKSUMS")
[[ "$EXPECTED_SHA" =~ ^[0-9a-fA-F]{64}$ ]] \
    || { echo "❌ ctop checksum manifest is missing a valid digest for $CTOP_ASSET"; exit 1; }
echo "$EXPECTED_SHA  $TMP/ctop" | sha256sum --check --quiet
echo "✅ Checksum verified"

sudo install -m 0755 "$TMP/ctop" "$BIN_DIR/ctop"

if ! command -v ctop &>/dev/null; then
    echo "❌ ctop installation failed or is not in PATH"
    exit 1
fi

echo ""
echo "✅ ctop installed ($(ctop -v 2>/dev/null | head -1)) → $BIN_DIR/ctop"
echo "💡 Live per-container CPU/memory/net/IO: ctop"
echo "💡 Include stopped containers: ctop -a"
echo "💡 Needs dev/docker.sh (or an existing Docker install) to be useful"
