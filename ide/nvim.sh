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

echo "🚀 Installing latest Neovim from official GitHub release..."

INSTALL_DIR="${NVIM_INSTALL_DIR:-$HOME/.local/share/nvim-stable}"
BIN_DIR="$HOME/.local/bin"
NVIM_BIN="$BIN_DIR/nvim"

HOME_CANON=$(realpath -m "$HOME")
INSTALL_DIR=$(realpath -m "$INSTALL_DIR")
case "$INSTALL_DIR" in
    "$HOME_CANON"/*) ;;
    *) echo "❌ NVIM_INSTALL_DIR must resolve beneath HOME"; exit 1 ;;
esac
INSTALL_RELATIVE=${INSTALL_DIR#"$HOME_CANON"/}
INSTALL_BASENAME=${INSTALL_DIR##*/}
if [[ "$INSTALL_RELATIVE" != */* ]] || [[ ! "$INSTALL_BASENAME" =~ ^nvim($|-) ]]; then
    echo "❌ Unsafe NVIM_INSTALL_DIR: require at least two components beneath HOME and basename nvim or nvim-*"
    exit 1
fi
case "$INSTALL_RELATIVE" in
    .config/*|.ssh/*|.gnupg/*|.aws/*|.kube/*|.password-store/*|.local/bin/*)
        echo "❌ Unsafe NVIM_INSTALL_DIR: protected user configuration, secret, and executable paths are not install targets"
        exit 1
        ;;
esac
if [[ -e "$INSTALL_DIR" || -L "$INSTALL_DIR" ]] \
    && { [[ ! -x "$INSTALL_DIR/bin/nvim" ]] || ! "$INSTALL_DIR/bin/nvim" --version &>/dev/null; }; then
    echo "❌ Refusing to replace $INSTALL_DIR because it is not a valid existing Neovim installation"
    exit 1
fi

# Skip if a recent enough nvim is on PATH
if command -v nvim &>/dev/null; then
    INSTALLED=$(nvim --version | head -1 | awk '{print $2}' | tr -d 'v')
    echo "✅ Neovim $INSTALLED already on PATH ($(command -v nvim))"
    echo "💡 To force a reinstall, remove $INSTALL_DIR and re-run."
    exit 0
fi

# Resolve latest release tag
echo "🔍 Resolving latest Neovim release..."
NVIM_VERSION="${NVIM_VERSION:-}"
if [ -z "$NVIM_VERSION" ]; then
    NVIM_VERSION=$(latest_github_tag neovim/neovim)
fi
echo "📥 Neovim $NVIM_VERSION"

# Pick correct asset for arch (Neovim ships nvim-linux-x86_64 / nvim-linux-arm64)
ARCH_RAW=$(uname -m)
case "$ARCH_RAW" in
    x86_64)  ASSET="nvim-linux-x86_64.tar.gz" ;;
    aarch64) ASSET="nvim-linux-arm64.tar.gz"  ;;
    *) echo "❌ Unsupported architecture: $ARCH_RAW"; exit 1 ;;
esac

URL="${NVIM_ARCHIVE_URL:-https://github.com/neovim/neovim/releases/download/${NVIM_VERSION}/${ASSET}}"

TMP=$(mktemp -d)
STAGE=""
BACKUP=""
cleanup() {
    rm -rf "$TMP"
    [ -z "$STAGE" ] || rm -rf "$STAGE"
    if [ -n "$BACKUP" ] && [ -e "$BACKUP" ] && [ ! -e "$INSTALL_DIR" ]; then
        mv "$BACKUP" "$INSTALL_DIR" || echo "⚠️  Previous install retained at $BACKUP" >&2
    fi
}
trap cleanup EXIT
wget --tries=3 --waitretry=2 -q --show-progress -O "$TMP/nvim.tar.gz" "$URL"

# A custom mirror is untrusted, so it must always declare its digest.
EXPECTED_SHA="${NVIM_ARCHIVE_SHA256:-}"
if [ -z "$EXPECTED_SHA" ] && [ -n "${NVIM_ARCHIVE_URL:-}" ]; then
    echo "❌ A custom Neovim archive requires NVIM_ARCHIVE_SHA256"
    exit 1
fi

# Upstream's checksum publishing has moved around: v0.10.x shipped a per-asset
# <asset>.sha256sum, v0.11.0 shipped an aggregate shasum.txt, and v0.11.4 and
# later publish neither. Try both locations and verify whenever upstream gives
# us something to verify against.
if [ -z "$EXPECTED_SHA" ]; then
    RELEASE_BASE="${URL%/*}"
    if wget --tries=3 --waitretry=2 -q -O "$TMP/asset.sha256sum" "${URL}.sha256sum"; then
        EXPECTED_SHA=$(awk 'NR==1 {print $1}' "$TMP/asset.sha256sum")
    elif wget --tries=3 --waitretry=2 -q -O "$TMP/shasum.txt" "${RELEASE_BASE}/shasum.txt"; then
        EXPECTED_SHA=$(awk -v want="$ASSET" '$2 == want || $2 == "*" want {print $1; exit}' "$TMP/shasum.txt")
    fi
fi

if [ -n "$EXPECTED_SHA" ]; then
    echo "$EXPECTED_SHA  $TMP/nvim.tar.gz" | sha256sum --check --quiet
    echo "✅ Checksum verified"
else
    echo "⚠️  Neovim $NVIM_VERSION publishes no checksum asset — cannot verify the download"
    echo "   Fetched over TLS from github.com; set NVIM_ARCHIVE_SHA256 to enforce a digest."
fi

# Build and validate away from the destination, then replace it atomically.
INSTALL_PARENT=$(dirname "$INSTALL_DIR")
mkdir -p "$INSTALL_PARENT"
STAGE=$(mktemp -d "$INSTALL_PARENT/.nvim-stage.XXXXXX")
tar -xzf "$TMP/nvim.tar.gz" -C "$STAGE" --strip-components=1
if [ ! -x "$STAGE/bin/nvim" ] || ! "$STAGE/bin/nvim" --version &>/dev/null; then
    echo "❌ Downloaded archive does not contain a working Neovim binary"
    exit 1
fi

if [ -e "$INSTALL_DIR" ]; then
    BACKUP=$(mktemp -d "$INSTALL_PARENT/.nvim-backup.XXXXXX")
    rmdir "$BACKUP"
    mv "$INSTALL_DIR" "$BACKUP"
fi
if ! mv "$STAGE" "$INSTALL_DIR"; then
    if [ -n "$BACKUP" ] && mv "$BACKUP" "$INSTALL_DIR"; then
        BACKUP=""
    fi
    echo "❌ Could not replace Neovim installation"
    exit 1
fi
STAGE=""
if [ -n "$BACKUP" ]; then
    rm -rf "$BACKUP"
    BACKUP=""
fi

# Link the validated install into ~/.local/bin.
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
