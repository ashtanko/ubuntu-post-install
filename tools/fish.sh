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

echo "🚀 Installing Fish shell..."

declare -a REQUIRED_PACKAGES=()
command -v fish &>/dev/null || REQUIRED_PACKAGES+=(fish)
command -v curl &>/dev/null || REQUIRED_PACKAGES+=(curl)
command -v git &>/dev/null || REQUIRED_PACKAGES+=(git)

if [ "${#REQUIRED_PACKAGES[@]}" -gt 0 ]; then
    echo "📦 Installing Fish prerequisites: ${REQUIRED_PACKAGES[*]}..."
    sudo apt-get update
    sudo apt-get install -y "${REQUIRED_PACKAGES[@]}"
fi
echo "✅ Fish installed ($(fish --version))"

FISH_PATH=$(command -v fish)
USERNAME="${USER:-$(id -un)}"

# Fish installed from apt is normally registered already. Keep this guard for
# custom packages and older Ubuntu releases where that may not be true.
if ! grep -qxF "$FISH_PATH" /etc/shells; then
    echo "🐚 Registering Fish in /etc/shells..."
    printf '%s\n' "$FISH_PATH" | sudo tee -a /etc/shells >/dev/null
fi

if [ "${SET_FISH_AS_DEFAULT:-yes}" = "no" ]; then
    echo "⏭️  Leaving the default shell unchanged (SET_FISH_AS_DEFAULT=no)"
else
    CURRENT_SHELL=$(getent passwd "$USERNAME" | cut -d: -f7)
    if [ "$CURRENT_SHELL" = "$FISH_PATH" ]; then
        echo "✅ Fish is already the default shell"
    else
        echo "🐚 Setting Fish as the default shell..."
        sudo chsh -s "$FISH_PATH" "$USERNAME"
        echo "⚠️  Log out and back in for the shell change to take effect"
    fi
fi

# Fisher is a maintained, lightweight Fish plugin manager. Oh My Fish now
# describes itself as unmaintained, so new installs use Fisher instead.
if [ "${INSTALL_FISHER:-yes}" = "no" ]; then
    echo "⏭️  Skipping Fisher (INSTALL_FISHER=no)"
elif [ -f "$HOME/.config/fish/functions/fisher.fish" ]; then
    echo "✅ Fisher already installed"
else
    echo "✨ Installing Fisher plugin manager..."
    FISHER_INSTALLER=$(mktemp)
    trap 'rm -f "$FISHER_INSTALLER"' EXIT
    curl -fsSL --retry 3 --retry-all-errors -o "$FISHER_INSTALLER" \
        https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish
    # Fish expands this variable after Bash starts the child process.
    # shellcheck disable=SC2016
    FISHER_BOOTSTRAP="$FISHER_INSTALLER" fish -c \
        'source "$FISHER_BOOTSTRAP"; fisher install jorgebucaran/fisher'
    rm -f "$FISHER_INSTALLER"
    trap - EXIT
    echo "✅ Fisher installed"
fi

echo "✅ Fish setup complete!"
echo "💡 Start it now with: fish"
