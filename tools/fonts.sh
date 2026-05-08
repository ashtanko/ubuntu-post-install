#!/bin/bash
set -euo pipefail

# Re-exec under bash if invoked via `sh` (dash mishandles &>, [[ ]], etc.)
if [ -z "${BASH_VERSION:-}" ]; then
    exec /bin/bash "$0" "$@"
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ -f "$REPO_ROOT/.env" ]] && { set -a; source "$REPO_ROOT/.env"; set +a; }

echo "🚀 Installing developer Nerd Fonts..."

# fontconfig provides fc-cache / fc-list (missing on minimal Ubuntu)
if ! command -v fc-cache &>/dev/null; then
    echo "📦 Installing fontconfig..."
    sudo apt-get update
    sudo apt-get install -y fontconfig
fi

FONTS_DIR="$HOME/.local/share/fonts"
mkdir -p "$FONTS_DIR"

# Fetch latest nerd-fonts release tag once
NERD_VERSION=$(curl -fsSL https://api.github.com/repos/ryanoasis/nerd-fonts/releases/latest \
    | grep '"tag_name"' | cut -d'"' -f4)
echo "📋 Nerd Fonts version: $NERD_VERSION"

install_nerd_font() {
    local name="$1"       # e.g. JetBrainsMono
    local check="$2"      # grep pattern to detect if already installed
    local url="https://github.com/ryanoasis/nerd-fonts/releases/download/${NERD_VERSION}/${name}.tar.xz"

    if fc-list | grep -qi "$check"; then
        echo "✅ $name already installed"
        return
    fi

    echo "📥 Downloading $name Nerd Font..."
    TMP=$(mktemp -d)
    trap 'rm -rf "$TMP"' RETURN

    wget -q --show-progress -O "$TMP/${name}.tar.xz" "$url"
    tar -xJf "$TMP/${name}.tar.xz" -C "$FONTS_DIR" --wildcards '*.ttf' '*.otf' 2>/dev/null || true
    echo "✅ $name installed"
}

install_nerd_font "JetBrainsMono" "JetBrainsMono"
install_nerd_font "FiraCode"      "FiraCode"
install_nerd_font "Hack"          "Hack Nerd"

echo "🔄 Refreshing font cache..."
fc-cache -fv > /dev/null

echo ""
echo "✅ Fonts installed!"
echo "   JetBrains Mono Nerd Font"
echo "   Fira Code Nerd Font"
echo "   Hack Nerd Font"
echo "💡 Set your terminal font to one of the above to see icons properly"
