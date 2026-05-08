#!/bin/bash
set -euo pipefail

# Re-exec under bash if invoked via `sh` (dash mishandles &>, [[ ]], etc.)
if [ -z "${BASH_VERSION:-}" ]; then
    exec /bin/bash "$0" "$@"
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ -f "$REPO_ROOT/.env" ]] && { set -a; source "$REPO_ROOT/.env"; set +a; }

echo "🚀 Installing CLI developer tools..."

ARCH=$(dpkg --print-architecture)

install_if_missing() {
    local cmd="$1"
    local pkg="$2"
    if command -v "$cmd" &>/dev/null; then
        echo "✅ $cmd already installed"
    else
        echo "📦 Installing $pkg..."
        sudo apt-get install -y "$pkg"
    fi
}

sudo apt-get update

# Standard apt packages
install_if_missing bat bat
install_if_missing fzf fzf
install_if_missing rg  ripgrep
install_if_missing jq  jq
install_if_missing htop htop
install_if_missing tmux tmux
install_if_missing tree tree

# eza — modern ls replacement (not in older apt, use GitHub release)
if command -v eza &>/dev/null; then
    echo "✅ eza already installed"
else
    echo "📦 Installing eza..."
    # eza release names use x86_64 / aarch64, not the Debian arch names
    case "$ARCH" in
        amd64) EZA_ARCH="x86_64" ;;
        arm64) EZA_ARCH="aarch64" ;;
        *)     EZA_ARCH="$ARCH" ;;
    esac
    EZA_VERSION=$(curl -fsSL https://api.github.com/repos/eza-community/eza/releases/latest \
        | grep '"tag_name"' | cut -d'"' -f4)
    EZA_URL="https://github.com/eza-community/eza/releases/download/${EZA_VERSION}/eza_${EZA_ARCH}-unknown-linux-musl.tar.gz"
    TMP=$(mktemp -d)
    trap 'rm -rf "$TMP"' EXIT
    wget -q --show-progress -O "$TMP/eza.tar.gz" "$EZA_URL"
    tar -xzf "$TMP/eza.tar.gz" -C "$TMP"
    EZA_BIN=$(find "$TMP" -name eza -type f | head -1)
    [ -n "$EZA_BIN" ] || { echo "❌ eza binary not found in tarball"; exit 1; }
    sudo mv "$EZA_BIN" /usr/local/bin/eza
    sudo chmod +x /usr/local/bin/eza
    echo "✅ eza installed"
fi

# GitHub CLI — via GitHub's apt repository
if command -v gh &>/dev/null; then
    echo "✅ gh already installed ($(gh --version | head -1))"
else
    echo "📦 Adding GitHub CLI repository..."
    wget -qO- https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        | sudo tee /usr/share/keyrings/githubcli-archive-keyring.gpg > /dev/null
    sudo chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
    echo "deb [arch=${ARCH} signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] \
https://cli.github.com/packages stable main" \
        | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
    sudo apt-get update
    sudo apt-get install -y gh
    echo "✅ gh installed ($(gh --version | head -1))"
fi

echo ""
echo "✅ CLI tools installation complete!"
echo "   bat    - better cat with syntax highlighting"
echo "   fzf    - fuzzy finder"
echo "   rg     - ripgrep (fast grep)"
echo "   eza    - modern ls"
echo "   jq     - JSON processor"
echo "   htop   - interactive process viewer"
echo "   tmux   - terminal multiplexer"
echo "   tree   - directory tree viewer"
echo "   gh     - GitHub CLI"
