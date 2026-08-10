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

echo "🚀 Installing Zsh..."

# Install Zsh
if command -v zsh &>/dev/null; then
    echo "✅ Zsh already installed ($(zsh --version))"
else
    echo "📦 Installing Zsh..."
    sudo apt update
    sudo apt install -y zsh
fi

# Change default shell
USERNAME="${USER:-$(id -un)}"
CURRENT_SHELL=$(getent passwd "$USERNAME" | cut -d: -f7)
ZSH_PATH=$(which zsh)
if [ "$CURRENT_SHELL" = "$ZSH_PATH" ]; then
    echo "✅ Zsh is already the default shell"
else
    echo "🐚 Setting Zsh as default shell..."
    sudo chsh -s "$ZSH_PATH" "$USERNAME"
    echo "⚠️  Log out and back in for the shell change to take effect"
fi

# Oh My Zsh — non-interactive: set INSTALL_OH_MY_ZSH=yes/no, default yes
if [ -d "$HOME/.oh-my-zsh" ]; then
    echo "✅ Oh My Zsh already installed"
else
    INSTALL_OMZ="${INSTALL_OH_MY_ZSH:-yes}"
    if [ "$INSTALL_OMZ" != "no" ]; then
        echo "✨ Installing Oh My Zsh..."
        OMZ_INSTALLER=$(mktemp)
        trap 'rm -f "$OMZ_INSTALLER"' EXIT
        curl -fsSL --retry 3 --retry-all-errors -o "$OMZ_INSTALLER" \
            https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh
        sh "$OMZ_INSTALLER" --unattended
        rm -f "$OMZ_INSTALLER"
        trap - EXIT
        echo "✅ Oh My Zsh installed"
    else
        echo "⏭️  Skipping Oh My Zsh (INSTALL_OH_MY_ZSH=no)"
    fi
fi

echo "✅ Zsh setup complete!"
