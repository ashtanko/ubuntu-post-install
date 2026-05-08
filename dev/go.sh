#!/bin/bash
set -euo pipefail

# Re-exec under bash if invoked via `sh` (dash mishandles &>, [[ ]], etc.)
if [ -z "${BASH_VERSION:-}" ]; then
    exec /bin/bash "$0" "$@"
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ -f "$REPO_ROOT/.env" ]] && { set -a; source "$REPO_ROOT/.env"; set +a; }

echo "🚀 Installing Go..."

GO_INSTALL_DIR="${GO_INSTALL_DIR:-/usr/local/go}"

if [ -d "$GO_INSTALL_DIR" ]; then
    echo "✅ Go already installed ($($GO_INSTALL_DIR/bin/go version))"
    echo "💡 To upgrade: remove /usr/local/go and re-run this script"
    exit 0
fi

# Fetch latest stable version number.
# Primary source: https://go.dev/VERSION?m=text (undocumented but historically stable).
# Fallback: parse the documented JSON at https://go.dev/dl/?mode=json — pick the
# first entry where stable=true.
echo "🔍 Fetching latest Go version..."
GO_VERSION=$(curl -fsSL "https://go.dev/VERSION?m=text" 2>/dev/null | head -1 || true)

if [[ ! "$GO_VERSION" =~ ^go[0-9] ]]; then
    echo "⚠️  Primary version endpoint returned unexpected output — falling back to dl/?mode=json"
    GO_VERSION=$(curl -fsSL "https://go.dev/dl/?mode=json" \
        | python3 -c "
import sys, json
data = json.load(sys.stdin)
for r in data:
    if r.get('stable'):
        print(r['version'])
        sys.exit(0)
" || true)
fi

if [[ ! "$GO_VERSION" =~ ^go[0-9] ]]; then
    echo "❌ Could not determine the latest Go version from go.dev"
    exit 1
fi
echo "📥 Latest Go: $GO_VERSION"

ARCH=$(dpkg --print-architecture)
# dpkg uses 'amd64'/'arm64' which matches Go's naming
TARBALL="${GO_VERSION}.linux-${ARCH}.tar.gz"
URL="https://go.dev/dl/${TARBALL}"

echo "📦 Downloading $TARBALL..."
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

wget -q --show-progress -O "$TMP/$TARBALL" "$URL"

# Verify checksum
echo "🔒 Verifying checksum..."
EXPECTED_SHA=$(curl -fsSL "https://go.dev/dl/?mode=json" \
    | python3 -c "
import sys, json
data = json.load(sys.stdin)
for release in data:
    for f in release.get('files', []):
        if f['filename'] == '${TARBALL}':
            print(f['sha256'])
            sys.exit(0)
")

if [ -n "$EXPECTED_SHA" ]; then
    echo "$EXPECTED_SHA  $TMP/$TARBALL" | sha256sum --check --quiet
    echo "✅ Checksum verified"
else
    echo "⚠️  Could not fetch checksum — proceeding without verification"
fi

echo "📦 Extracting to $GO_INSTALL_DIR..."
sudo tar -C /usr/local -xzf "$TMP/$TARBALL"

# Persist PATH in shell configs
GO_PATH_LINE="export PATH=\$PATH:${GO_INSTALL_DIR}/bin"
for RC in "$HOME/.zshrc" "$HOME/.bashrc"; do
    if [ -f "$RC" ] && ! grep -q "${GO_INSTALL_DIR}/bin" "$RC"; then
        echo "" >> "$RC"
        echo "# Go SDK" >> "$RC"
        echo "$GO_PATH_LINE" >> "$RC"
        echo "✅ Added Go to PATH in $RC"
    fi
done

export PATH=$PATH:${GO_INSTALL_DIR}/bin

echo ""
echo "✅ Go installed!"
echo "   $(go version)"
echo "💡 Reload your shell or run: source ~/.zshrc"
