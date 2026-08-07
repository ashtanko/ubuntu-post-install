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

# Resolve the newest release tag of a GitHub repo without calling api.github.com —
# unauthenticated API calls are rate-limited per IP and start returning 403 in CI.
# Follows the /releases/latest redirect and reads the tag back out of the URL.
latest_github_tag() {
    local repo="$1" url
    url=$(curl -fsSLI --retry 3 --retry-all-errors -o /dev/null -w '%{url_effective}' "https://github.com/${repo}/releases/latest")
    case "$url" in
        */releases/tag/*) printf '%s\n' "${url##*/releases/tag/}" ;;
        *) echo "❌ Could not resolve latest release for $repo" >&2; return 1 ;;
    esac
}

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
