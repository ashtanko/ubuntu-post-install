#!/bin/bash
set -euo pipefail

# Re-exec under bash if invoked via `sh` (dash mishandles &>, [[ ]], etc.)
if [ -z "${BASH_VERSION:-}" ]; then
    exec /bin/bash "$0" "$@"
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ -f "$REPO_ROOT/.env" ]] && { set -a; source "$REPO_ROOT/.env"; set +a; }

echo "🚀 Installing Postman..."

INSTALL_DIR="${POSTMAN_INSTALL_DIR:-$HOME/.local/share/Postman}"
BIN_LINK="$HOME/.local/bin/postman"
DESKTOP_FILE="$HOME/.local/share/applications/postman.desktop"
POSTMAN_BIN="$INSTALL_DIR/Postman"

if [ -x "$POSTMAN_BIN" ]; then
    echo "✅ Postman already installed at $INSTALL_DIR"
    echo "💡 Postman self-updates; remove $INSTALL_DIR to force reinstall."
    exit 0
fi

case "$(uname -m)" in
    x86_64)         ARCH="linux_64" ;;
    aarch64|arm64)  ARCH="linux_arm64" ;;
    *) echo "❌ Unsupported architecture: $(uname -m)"; exit 1 ;;
esac

echo "📦 Ensuring curl + tar are present..."
sudo apt-get install -y curl tar

echo "🔍 Downloading Postman ($ARCH)..."
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
curl -fL --progress-bar -o "$TMP/postman.tar.gz" \
    "https://dl.pstmn.io/download/latest/$ARCH"

mkdir -p "$INSTALL_DIR"
tar -xzf "$TMP/postman.tar.gz" -C "$INSTALL_DIR" --strip-components=1

if [ ! -x "$POSTMAN_BIN" ]; then
    echo "❌ Postman binary missing after extract"
    exit 1
fi

mkdir -p "$(dirname "$BIN_LINK")"
ln -sf "$POSTMAN_BIN" "$BIN_LINK"

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
Name=Postman
Exec=$POSTMAN_BIN
Icon=$INSTALL_DIR/app/icons/icon_128x128.png
Categories=Development;
Terminal=false
StartupWMClass=Postman
EOF

echo ""
echo "✅ Postman installed at $INSTALL_DIR"
echo "💡 Launch from the application menu, or run: postman"
