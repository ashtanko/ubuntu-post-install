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

if ! DIVE_BIN=$(command -v dive 2>/dev/null); then
    echo "⏭️  Skipping dive update: dive is not installed."
    exit 0
fi
if ! dpkg-query -W -f='${Status}' dive 2>/dev/null | grep -q 'ok installed' \
    || ! dpkg-query -S "$DIVE_BIN" 2>/dev/null | grep -q '^dive:'; then
    echo "⏭️  Skipping dive update: the active binary is not owned by the release package installed by this project."
    exit 0
fi

ARCH=$(dpkg --print-architecture)
case "$ARCH" in
    amd64|arm64) ;;
    *) echo "❌ Unsupported dive architecture: $ARCH" >&2; exit 1 ;;
esac

DIVE_VERSION=$(latest_github_tag wagoodman/dive)
DIVE_NUM=${DIVE_VERSION#v}
INSTALLED_VERSION=$(dpkg-query -W -f='${Version}' dive 2>/dev/null || true)
if [ "$INSTALLED_VERSION" = "$DIVE_NUM" ]; then
    echo "✅ dive is already current ($DIVE_VERSION)."
    exit 0
fi

DIVE_ASSET="dive_${DIVE_NUM}_linux_${ARCH}.deb"
DIVE_BASE="https://github.com/wagoodman/dive/releases/download/${DIVE_VERSION}"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

BEFORE_VERSION=$("$DIVE_BIN" --version 2>/dev/null | head -1 || true)
echo "🚀 Updating dive..."
echo "   Before: ${BEFORE_VERSION:-version unknown}"
wget --tries=3 --waitretry=2 -nv --show-progress \
    -O "$TMP/$DIVE_ASSET" "${DIVE_BASE}/${DIVE_ASSET}"
curl --proto '=https' --tlsv1.2 -fsSL --retry 3 --retry-all-errors \
    -o "$TMP/checksums.txt" "${DIVE_BASE}/dive_${DIVE_NUM}_checksums.txt"
EXPECTED_SHA=$(awk -v want="$DIVE_ASSET" '$2 == want {print $1; exit}' "$TMP/checksums.txt")
[[ "$EXPECTED_SHA" =~ ^[0-9a-fA-F]{64}$ ]] \
    || { echo "❌ dive checksum manifest has no valid digest for $DIVE_ASSET" >&2; exit 1; }
echo "$EXPECTED_SHA  $TMP/$DIVE_ASSET" | sha256sum --check --quiet

sudo apt-get install -y "$TMP/$DIVE_ASSET"
AFTER_VERSION=$("$DIVE_BIN" --version 2>/dev/null | head -1 || true)
echo "✅ dive update complete"
echo "   After:  ${AFTER_VERSION:-version unknown}"
