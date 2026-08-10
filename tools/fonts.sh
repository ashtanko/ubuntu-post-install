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
NERD_VERSION=$(latest_github_tag ryanoasis/nerd-fonts)
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
    (
        local tmp
        local -a font_files
        tmp=$(mktemp -d)
        trap 'rm -rf "$tmp"' EXIT

        wget --tries=3 --waitretry=2 -q --show-progress -O "$tmp/${name}.tar.xz" "$url"
        mkdir -p "$tmp/extracted"
        tar -xJf "$tmp/${name}.tar.xz" -C "$tmp/extracted" \
            --wildcards --no-anchored '*.[ot]tf'
        mapfile -d '' -t font_files < <(find "$tmp/extracted" -type f \
            \( -iname '*.ttf' -o -iname '*.otf' \) -print0)
        if [ "${#font_files[@]}" -eq 0 ]; then
            echo "❌ $name archive contained no TTF or OTF font files"
            exit 1
        fi
        install -m 644 "${font_files[@]}" "$FONTS_DIR/"
    )
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
