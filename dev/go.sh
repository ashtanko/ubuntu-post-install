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

echo "🚀 Installing Go..."

GO_INSTALL_DIR="${GO_INSTALL_DIR:-/usr/local/go}"

if [ -e "$GO_INSTALL_DIR" ]; then
    if [ -x "$GO_INSTALL_DIR/bin/go" ] && "$GO_INSTALL_DIR/bin/go" version &>/dev/null; then
        echo "✅ Go already installed ($("$GO_INSTALL_DIR"/bin/go version))"
        echo "💡 To upgrade: remove $GO_INSTALL_DIR and re-run this script"
        exit 0
    fi
    echo "❌ $GO_INSTALL_DIR exists but is not a complete Go installation"
    echo "💡 Move or remove it, then re-run this script"
    exit 1
fi

# Fetch latest stable version number.
# Primary source: https://go.dev/VERSION?m=text (undocumented but historically stable).
# Fallback: parse the documented JSON at https://go.dev/dl/?mode=json — pick the
# first entry where stable=true.
echo "🔍 Fetching latest Go version..."
GO_VERSION="${GO_VERSION:-}"
GO_VERSION_METADATA=$(mktemp)
trap 'rm -f "$GO_VERSION_METADATA"' EXIT
if [ -z "$GO_VERSION" ]; then
    if curl -fsSL --retry 3 --retry-all-errors -o "$GO_VERSION_METADATA" \
        "https://go.dev/VERSION?m=text" 2>/dev/null; then
        GO_VERSION=$(head -1 "$GO_VERSION_METADATA" || true)
    fi
fi

if [[ ! "$GO_VERSION" =~ ^go[0-9] ]]; then
    echo "⚠️  Primary version endpoint returned unexpected output — falling back to dl/?mode=json"
    if curl -fsSL --retry 3 --retry-all-errors -o "$GO_VERSION_METADATA" \
        "https://go.dev/dl/?mode=json"; then
        GO_VERSION=$(python3 -c "
import sys, json
data = json.load(sys.stdin)
for r in data:
    if r.get('stable'):
        print(r['version'])
        sys.exit(0)
" < "$GO_VERSION_METADATA" || true)
    fi
fi
rm -f "$GO_VERSION_METADATA"
trap - EXIT

if [[ ! "$GO_VERSION" =~ ^go[0-9] ]]; then
    echo "❌ Could not determine the latest Go version from go.dev"
    exit 1
fi
echo "📥 Latest Go: $GO_VERSION"

ARCH=$(dpkg --print-architecture)
# dpkg uses 'amd64'/'arm64' which matches Go's naming
TARBALL="${GO_VERSION}.linux-${ARCH}.tar.gz"
URL="${GO_ARCHIVE_URL:-https://go.dev/dl/${TARBALL}}"

echo "📦 Downloading $TARBALL..."
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

wget --tries=3 --waitretry=2 -nv --show-progress -O "$TMP/$TARBALL" "$URL"

# Verify checksum
echo "🔒 Verifying checksum..."
EXPECTED_SHA="${GO_ARCHIVE_SHA256:-}"
if [ -z "$EXPECTED_SHA" ] && [ -z "${GO_ARCHIVE_URL:-}" ]; then
    GO_RELEASES_JSON="$TMP/go-releases.json"
    curl -fsSL --retry 3 --retry-all-errors -o "$GO_RELEASES_JSON" \
        "https://go.dev/dl/?mode=json"
    EXPECTED_SHA=$(python3 -c "
import sys, json
data = json.load(sys.stdin)
for release in data:
    for f in release.get('files', []):
        if f['filename'] == '${TARBALL}':
            print(f['sha256'])
            sys.exit(0)
" < "$GO_RELEASES_JSON")
fi

if [ -n "$EXPECTED_SHA" ]; then
    echo "$EXPECTED_SHA  $TMP/$TARBALL" | sha256sum --check --quiet
    echo "✅ Checksum verified"
else
    echo "❌ Could not obtain a checksum; refusing an unverified Go archive"
    exit 1
fi

echo "📦 Extracting to $GO_INSTALL_DIR..."
mkdir -p "$TMP/extract"
tar -C "$TMP/extract" -xzf "$TMP/$TARBALL"
if [ ! -x "$TMP/extract/go/bin/go" ] || ! "$TMP/extract/go/bin/go" version &>/dev/null; then
    echo "❌ Downloaded archive does not contain a working Go installation"
    exit 1
fi

INSTALL_PARENT=$(dirname "$GO_INSTALL_DIR")
if [[ "$INSTALL_PARENT" == "$HOME" || "$INSTALL_PARENT" == "$HOME"/* ]]; then
    mkdir -p "$INSTALL_PARENT"
    mv "$TMP/extract/go" "$GO_INSTALL_DIR"
elif [ -d "$INSTALL_PARENT" ] && [ -w "$INSTALL_PARENT" ]; then
    mv "$TMP/extract/go" "$GO_INSTALL_DIR"
else
    sudo mkdir -p "$INSTALL_PARENT"
    sudo mv "$TMP/extract/go" "$GO_INSTALL_DIR"
fi

# Persist PATH in shell configs
GO_PATH_LINE="export PATH=\$PATH:${GO_INSTALL_DIR}/bin"
for RC in "$HOME/.zshrc" "$HOME/.bashrc"; do
    if [ -f "$RC" ] && ! grep -q "${GO_INSTALL_DIR}/bin" "$RC"; then
        {
            echo ""
            echo "# Go SDK"
            echo "$GO_PATH_LINE"
        } >> "$RC"
        echo "✅ Added Go to PATH in $RC"
    fi
done

export PATH="$PATH:${GO_INSTALL_DIR}/bin"

echo ""
echo "✅ Go installed!"
echo "   $("$GO_INSTALL_DIR/bin/go" version)"
echo "💡 Reload your shell or run: source ~/.zshrc"
