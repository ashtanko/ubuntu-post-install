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

echo "🚀 Installing Cursor editor..."

# GUI complement to ai/cursor-agent.sh, which only installs the headless CLI agent.
ARCH=$(dpkg --print-architecture 2>/dev/null || uname -m)
if [ "$ARCH" != "amd64" ] && [ "$ARCH" != "x86_64" ]; then
    echo "❌ Cursor only publishes a Linux x64 AppImage (detected: $ARCH)."
    exit 1
fi

INSTALL_DIR="${CURSOR_INSTALL_DIR:-$HOME/.local/share/Cursor}"
APPIMAGE="$INSTALL_DIR/Cursor.AppImage"
BIN_LINK="$HOME/.local/bin/cursor"
DESKTOP_FILE="$HOME/.local/share/applications/cursor.desktop"

if [ -x "$APPIMAGE" ]; then
    echo "✅ Cursor already installed at $INSTALL_DIR"
    echo "💡 Cursor self-updates; remove $INSTALL_DIR to force reinstall."
    exit 0
fi

# AppImages run through FUSE — same requirement as ide/jetbrains-toolbox.sh,
# and missing by default on 24.04+.
echo "📦 Ensuring libfuse2 is present..."
sudo apt-get update
sudo apt-get install -y libfuse2 || sudo apt-get install -y libfuse2t64

echo "📥 Downloading Cursor (official \"latest\" redirect)..."
mkdir -p "$INSTALL_DIR"
curl -fL --progress-bar --retry 3 --retry-all-errors -o "$APPIMAGE" \
    "https://downloader.cursor.sh/linux/appImage/x64"
chmod +x "$APPIMAGE"

if [ ! -x "$APPIMAGE" ]; then
    echo "❌ Cursor download failed"
    exit 1
fi

mkdir -p "$(dirname "$BIN_LINK")"
ln -sf "$APPIMAGE" "$BIN_LINK"

# shellcheck disable=SC2016
PATH_LINE='[ -d "$HOME/.local/bin" ] && case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) export PATH="$HOME/.local/bin:$PATH";; esac'
for RC in "$HOME/.zshrc" "$HOME/.bashrc"; do
    [ -f "$RC" ] || continue
    # shellcheck disable=SC2016
    grep -qF '$HOME/.local/bin' "$RC" || echo "$PATH_LINE" >> "$RC"
done

mkdir -p "$(dirname "$DESKTOP_FILE")"
cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Type=Application
Name=Cursor
Exec=$APPIMAGE --no-sandbox %F
Icon=cursor
Categories=Development;
Terminal=false
StartupWMClass=Cursor
EOF

echo ""
echo "✅ Cursor installed at $INSTALL_DIR"
echo "💡 Launch from the application menu, or run: cursor"
echo "💡 Custom install location: CURSOR_INSTALL_DIR=... bash ide/cursor.sh"
