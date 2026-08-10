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
if command -v bat &>/dev/null || command -v batcat &>/dev/null; then
    echo "✅ bat already installed"
else
    echo "📦 Installing bat..."
    sudo apt-get install -y bat
fi
install_if_missing fzf fzf
install_if_missing rg  ripgrep
install_if_missing jq  jq
install_if_missing htop htop
install_if_missing tmux tmux
install_if_missing tree tree

# Ubuntu's `bat` package ships its binary as `batcat` — an unrelated Debian
# package already claimed the name `bat` — so the `bat` command never resolves
# without a symlink, and the "already installed" check above never trips.
USER_BIN="$HOME/.local/bin"
mkdir -p "$USER_BIN"
if ! command -v bat &>/dev/null && command -v batcat &>/dev/null; then
    BATCAT_BIN=$(command -v batcat)
    BAT_LINK="$USER_BIN/bat"
    if [[ ! -e "$BAT_LINK" && ! -L "$BAT_LINK" ]]; then
        ln -s "$BATCAT_BIN" "$BAT_LINK"
        echo "✅ Symlinked bat → batcat"
    elif [[ -L "$BAT_LINK" && "$(readlink -f -- "$BAT_LINK")" == "$(readlink -f -- "$BATCAT_BIN")" ]]; then
        echo "✅ bat → batcat symlink already configured"
    else
        echo "⚠️  $BAT_LINK already exists and is not managed by this script; leaving it unchanged"
    fi
fi

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
    EZA_VERSION=$(latest_github_tag eza-community/eza)
    EZA_URL="https://github.com/eza-community/eza/releases/download/${EZA_VERSION}/eza_${EZA_ARCH}-unknown-linux-musl.tar.gz"
    TMP=$(mktemp -d)
    trap 'rm -rf "$TMP"' EXIT
    # eza publishes no checksum asset to verify against (fetched over TLS from
    # github.com); retry protects against a dropped connection, not tampering.
    wget --tries=3 --waitretry=2 -q --show-progress -O "$TMP/eza.tar.gz" "$EZA_URL"
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
    wget --tries=3 --waitretry=2 -qO- https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        | sudo tee /usr/share/keyrings/githubcli-archive-keyring.gpg > /dev/null
    sudo chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
    echo "deb [arch=${ARCH} signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] \
https://cli.github.com/packages stable main" \
        | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
    sudo apt-get update
    sudo apt-get install -y gh
    echo "✅ gh installed ($(gh --version | head -1))"
fi

# Ensure ~/.local/bin is on PATH (idempotent).
# Single quotes are intentional — `$HOME` / `$PATH` must be literal in the rc file.
# shellcheck disable=SC2016
PATH_LINE='[ -d "$HOME/.local/bin" ] && case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) export PATH="$HOME/.local/bin:$PATH";; esac'
PATH_MARKER="# ~/.local/bin (added by cli-tools.sh)"
has_active_local_bin_path() {
    local line
    while IFS= read -r line; do
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        if [[ "$line" == *PATH=*"\$HOME/.local/bin"* \
            || "$line" == *PATH=*"\${HOME}/.local/bin"* ]]; then
            return 0
        fi
    done < "$1"
    return 1
}

for RC in "$HOME/.zshrc" "$HOME/.bashrc"; do
    [ -f "$RC" ] || continue
    if grep -qF "$PATH_MARKER" "$RC" || has_active_local_bin_path "$RC"; then
        continue
    fi
    {
        echo ""
        echo "$PATH_MARKER"
        echo "$PATH_LINE"
    } >> "$RC"
    echo "✅ Added \$HOME/.local/bin to PATH in $RC"
done

echo ""
echo "✅ CLI tools installation complete!"
echo "   bat    - better cat with syntax highlighting (symlinked from batcat)"
echo "   fzf    - fuzzy finder"
echo "   rg     - ripgrep (fast grep)"
echo "   eza    - modern ls"
echo "   jq     - JSON processor"
echo "   htop   - interactive process viewer"
echo "   tmux   - terminal multiplexer"
echo "   tree   - directory tree viewer"
echo "   gh     - GitHub CLI"
