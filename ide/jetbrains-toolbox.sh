#!/bin/bash
set -euo pipefail

# Re-exec under bash if invoked via `sh` (dash mishandles &>, [[ ]], etc.)
if [ -z "${BASH_VERSION:-}" ]; then
    exec /bin/bash "$0" "$@"
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ -f "$REPO_ROOT/.env" ]] && { set -a; source "$REPO_ROOT/.env"; set +a; }

echo "🚀 Installing JetBrains Toolbox..."

INSTALL_DIR="${JETBRAINS_TOOLBOX_DIR:-$HOME/.local/share/JetBrains/Toolbox}"
TOOLBOX_BIN="$INSTALL_DIR/bin/jetbrains-toolbox"
DESKTOP_FILE="$HOME/.local/share/applications/jetbrains-toolbox.desktop"

if [ -x "$TOOLBOX_BIN" ]; then
    echo "✅ JetBrains Toolbox already installed at $INSTALL_DIR"
    echo "💡 Update from inside the Toolbox UI itself."
    exit 0
fi

# Toolbox needs libfuse2 to run on modern Ubuntu (24.04+ no longer ships it)
echo "📦 Ensuring libfuse2 is present..."
sudo apt update
sudo apt install -y libfuse2 || sudo apt install -y libfuse2t64

echo "🔍 Resolving latest JetBrains Toolbox download..."
META_URL="https://data.services.jetbrains.com/products/releases?code=TBA&latest=true&type=release"
DOWNLOAD_URL=$(curl -fsSL "$META_URL" | python3 -c "
import sys, json
data = json.load(sys.stdin)
print(data['TBA'][0]['downloads']['linux']['link'])
")

if [ -z "$DOWNLOAD_URL" ]; then
    echo "❌ Could not resolve Toolbox download URL"
    exit 1
fi
echo "📥 $DOWNLOAD_URL"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

wget -q --show-progress -O "$TMP/toolbox.tar.gz" "$DOWNLOAD_URL"

mkdir -p "$INSTALL_DIR"
tar -xzf "$TMP/toolbox.tar.gz" -C "$INSTALL_DIR" --strip-components=1

if [ ! -x "$TOOLBOX_BIN" ]; then
    echo "❌ Toolbox binary missing after extract"
    exit 1
fi

# Desktop entry so it shows up in the launcher
mkdir -p "$(dirname "$DESKTOP_FILE")"
cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Type=Application
Name=JetBrains Toolbox
Exec=$TOOLBOX_BIN
Icon=$INSTALL_DIR/jetbrains-toolbox.svg
Categories=Development;
Terminal=false
EOF

echo ""
echo "✅ JetBrains Toolbox installed."
echo "💡 Launch it from your application menu, sign in, then pick which IDEs"
echo "   (IntelliJ, PyCharm, GoLand, ...) to install through the Toolbox UI."
