#!/bin/bash
set -euo pipefail

# Re-exec under bash if invoked via `sh` (dash mishandles &>, [[ ]], etc.)
if [ -z "${BASH_VERSION:-}" ]; then
    exec /bin/bash "$0" "$@"
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ -f "$REPO_ROOT/.env" ]] && { set -a; source "$REPO_ROOT/.env"; set +a; }

echo "🚀 Installing modern CLI productivity extras..."

ARCH=$(dpkg --print-architecture)
case "$ARCH" in
    amd64) GO_ARCH="amd64"; RUST_ARCH="x86_64"; LAZYGIT_ARCH="x86_64" ;;
    arm64) GO_ARCH="arm64"; RUST_ARCH="aarch64"; LAZYGIT_ARCH="arm64" ;;
    *) echo "❌ Unsupported architecture: $ARCH"; exit 1 ;;
esac

BIN_DIR="/usr/local/bin"
USER_BIN="$HOME/.local/bin"
mkdir -p "$USER_BIN"

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

# --- apt-supplied packages ---
install_if_missing btop      btop
install_if_missing direnv    direnv
install_if_missing hyperfine hyperfine

# delta (git pager) — apt name is `git-delta` on 24.04+; fall back to GitHub release
if command -v delta &>/dev/null; then
    echo "✅ delta already installed"
elif apt-cache show git-delta &>/dev/null; then
    echo "📦 Installing delta from apt (git-delta)..."
    sudo apt-get install -y git-delta
else
    echo "🔍 Resolving latest delta release (apt package unavailable)..."
    DELTA_VERSION=$(curl -fsSL https://api.github.com/repos/dandavison/delta/releases/latest \
        | grep '"tag_name"' | cut -d'"' -f4)
    DELTA_URL="https://github.com/dandavison/delta/releases/download/${DELTA_VERSION}/git-delta-musl_${DELTA_VERSION}_${ARCH}.deb"
    DEB=$(mktemp --suffix=.deb)
    trap 'rm -f "$DEB"' EXIT
    wget -q --show-progress -O "$DEB" "$DELTA_URL"
    sudo apt-get install -y "$DEB"
    echo "✅ delta installed"
fi

# fd-find — binary ships as `fdfind`; symlink so `fd` works
install_if_missing fdfind fd-find
if [ ! -e "$USER_BIN/fd" ] && command -v fdfind &>/dev/null; then
    ln -s "$(command -v fdfind)" "$USER_BIN/fd"
    echo "✅ Symlinked fd → fdfind"
fi

# --- lazygit (GitHub release) ---
if command -v lazygit &>/dev/null; then
    echo "✅ lazygit already installed"
else
    echo "🔍 Resolving latest lazygit release..."
    LG_VERSION=$(curl -fsSL https://api.github.com/repos/jesseduffield/lazygit/releases/latest \
        | grep '"tag_name"' | cut -d'"' -f4)
    LG_NUM=${LG_VERSION#v}
    LG_URL="https://github.com/jesseduffield/lazygit/releases/download/${LG_VERSION}/lazygit_${LG_NUM}_Linux_${LAZYGIT_ARCH}.tar.gz"
    echo "📦 Downloading lazygit $LG_VERSION..."
    TMP=$(mktemp -d)
    trap 'rm -rf "$TMP"' EXIT
    wget -q --show-progress -O "$TMP/lazygit.tar.gz" "$LG_URL"
    tar -xzf "$TMP/lazygit.tar.gz" -C "$TMP"
    sudo install -m 0755 "$TMP/lazygit" "$BIN_DIR/lazygit"
    echo "✅ lazygit installed → $BIN_DIR/lazygit"
fi

# --- zoxide (official installer; lands in ~/.local/bin) ---
if command -v zoxide &>/dev/null; then
    echo "✅ zoxide already installed"
else
    echo "📦 Installing zoxide via official installer..."
    curl -fsSL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | bash
fi

# --- dust (GitHub release) ---
if command -v dust &>/dev/null; then
    echo "✅ dust already installed"
else
    echo "🔍 Resolving latest dust release..."
    DUST_VERSION=$(curl -fsSL https://api.github.com/repos/bootandy/dust/releases/latest \
        | grep '"tag_name"' | cut -d'"' -f4)
    DUST_URL="https://github.com/bootandy/dust/releases/download/${DUST_VERSION}/dust-${DUST_VERSION}-${RUST_ARCH}-unknown-linux-gnu.tar.gz"
    echo "📦 Downloading dust $DUST_VERSION..."
    TMP_D=$(mktemp -d)
    # shellcheck disable=SC2064
    trap "rm -rf '$TMP_D'" EXIT
    wget -q --show-progress -O "$TMP_D/dust.tar.gz" "$DUST_URL"
    tar -xzf "$TMP_D/dust.tar.gz" -C "$TMP_D" --strip-components=1
    sudo install -m 0755 "$TMP_D/dust" "$BIN_DIR/dust"
    echo "✅ dust installed → $BIN_DIR/dust"
fi

# --- tealdeer (`tldr` command — GitHub release) ---
if command -v tldr &>/dev/null; then
    echo "✅ tldr already installed"
else
    echo "🔍 Resolving latest tealdeer release..."
    TLDR_VERSION=$(curl -fsSL https://api.github.com/repos/tealdeer-rs/tealdeer/releases/latest \
        | grep '"tag_name"' | cut -d'"' -f4)
    TLDR_URL="https://github.com/tealdeer-rs/tealdeer/releases/download/${TLDR_VERSION}/tealdeer-linux-${RUST_ARCH}-musl"
    echo "📦 Downloading tealdeer $TLDR_VERSION..."
    TMP_T=$(mktemp)
    # shellcheck disable=SC2064
    trap "rm -f '$TMP_T'" EXIT
    wget -q --show-progress -O "$TMP_T" "$TLDR_URL"
    sudo install -m 0755 "$TMP_T" "$BIN_DIR/tldr"
    echo "✅ tldr installed → $BIN_DIR/tldr"
fi

# --- Shell integration for direnv + zoxide (idempotent rc-file edits) ---
for RC in "$HOME/.zshrc" "$HOME/.bashrc"; do
    [ -f "$RC" ] || continue
    SHELL_NAME=$(basename "$RC" | sed -E 's/^\.//;s/rc$//')   # zsh | bash

    if ! grep -q 'direnv hook' "$RC"; then
        {
            echo ""
            echo "# direnv"
            echo "eval \"\$(direnv hook $SHELL_NAME)\""
        } >> "$RC"
        echo "✅ Added direnv hook to $RC"
    fi

    if ! grep -q 'zoxide init' "$RC"; then
        {
            echo ""
            echo "# zoxide"
            echo "eval \"\$(zoxide init $SHELL_NAME)\""
        } >> "$RC"
        echo "✅ Added zoxide init to $RC"
    fi
done

# Silence unused-variable warning for GO_ARCH (kept for future Go-style asset URLs)
: "$GO_ARCH"

echo ""
echo "✅ Modern CLI extras installed!"
echo "   lazygit   - terminal UI for git"
echo "   delta     - syntax-highlighting pager for diffs"
echo "   zoxide    - smarter cd (z <partial-dir-name>)"
echo "   btop      - resource monitor"
echo "   direnv    - per-directory env vars"
echo "   fd        - friendlier find (symlinked from fd-find)"
echo "   dust      - disk usage with bars"
echo "   hyperfine - command-line benchmarking"
echo "   tldr      - simplified man pages"
echo "💡 Reload your shell to activate direnv + zoxide hooks"
