#!/bin/bash
set -euo pipefail

# Re-exec under bash if invoked via `sh` (dash mishandles &>, [[ ]], etc.)
if [ -z "${BASH_VERSION:-}" ]; then
    exec /bin/bash "$0" "$@"
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ -f "$REPO_ROOT/.env" ]] && { set -a; source "$REPO_ROOT/.env"; set +a; }

echo "🚀 Installing latest Neovim from official GitHub release..."

INSTALL_DIR="${NVIM_INSTALL_DIR:-$HOME/.local/share/nvim-stable}"
BIN_DIR="$HOME/.local/bin"
NVIM_BIN="$BIN_DIR/nvim"

# Skip if a recent enough nvim is on PATH
if command -v nvim &>/dev/null; then
    INSTALLED=$(nvim --version | head -1 | awk '{print $2}' | tr -d 'v')
    echo "✅ Neovim $INSTALLED already on PATH ($(command -v nvim))"
    echo "💡 To force a reinstall, remove $INSTALL_DIR and re-run."
    exit 0
fi

# Resolve latest release tag
echo "🔍 Resolving latest Neovim release..."
NVIM_VERSION=$(curl -fsSL https://api.github.com/repos/neovim/neovim/releases/latest \
    | grep '"tag_name"' | cut -d'"' -f4)
echo "📥 Neovim $NVIM_VERSION"

# Pick correct asset for arch (Neovim ships nvim-linux-x86_64 / nvim-linux-arm64)
ARCH_RAW=$(uname -m)
case "$ARCH_RAW" in
    x86_64)  ASSET="nvim-linux-x86_64.tar.gz" ;;
    aarch64) ASSET="nvim-linux-arm64.tar.gz"  ;;
    *) echo "❌ Unsupported architecture: $ARCH_RAW"; exit 1 ;;
esac

URL="https://github.com/neovim/neovim/releases/download/${NVIM_VERSION}/${ASSET}"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
wget -q --show-progress -O "$TMP/nvim.tar.gz" "$URL"

# Install into stable dir, link binary into ~/.local/bin
rm -rf "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR"
tar -xzf "$TMP/nvim.tar.gz" -C "$INSTALL_DIR" --strip-components=1
mkdir -p "$BIN_DIR"
ln -sf "$INSTALL_DIR/bin/nvim" "$NVIM_BIN"

# Ensure ~/.local/bin is on PATH (idempotent).
# Single quotes are intentional — `$HOME` / `$PATH` must be literal in the rc file.
# shellcheck disable=SC2016
PATH_LINE='[ -d "$HOME/.local/bin" ] && case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) export PATH="$HOME/.local/bin:$PATH";; esac'
for RC in "$HOME/.zshrc" "$HOME/.bashrc"; do
    # shellcheck disable=SC2016
    if [ -f "$RC" ] && ! grep -qF '$HOME/.local/bin' "$RC"; then
        {
            echo ""
            echo "# ~/.local/bin (added by nvim.sh)"
            echo "$PATH_LINE"
        } >> "$RC"
    fi
done

# Skeleton config if user has none
NVIM_CONFIG="$HOME/.config/nvim"
if [ ! -e "$NVIM_CONFIG/init.lua" ] && [ ! -e "$NVIM_CONFIG/init.vim" ]; then
    mkdir -p "$NVIM_CONFIG"
    cat > "$NVIM_CONFIG/init.lua" <<'LUA'
-- Minimal Neovim starter — extend or replace with your own config.
vim.opt.number         = true
vim.opt.relativenumber = true
vim.opt.expandtab      = true
vim.opt.shiftwidth     = 4
vim.opt.tabstop        = 4
vim.opt.smartcase      = true
vim.opt.ignorecase     = true
vim.opt.termguicolors  = true
vim.opt.clipboard      = "unnamedplus"
vim.g.mapleader        = " "
LUA
    echo "📝 Wrote starter $NVIM_CONFIG/init.lua"
fi

echo ""
echo "✅ Neovim $NVIM_VERSION installed → $NVIM_BIN"
echo "💡 Launch with: nvim"
