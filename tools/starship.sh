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

echo "🚀 Installing Starship cross-shell prompt..."

USER_BIN="$HOME/.local/bin"
mkdir -p "$USER_BIN"
export PATH="$USER_BIN:$PATH"

if command -v starship &>/dev/null; then
    echo "✅ Starship already installed ($(starship --version | head -1))"
else
    if ! command -v curl &>/dev/null; then
        echo "📦 Installing curl..."
        sudo apt-get update
        sudo apt-get install -y curl
    fi
    echo "📦 Installing Starship to $USER_BIN..."
    STARSHIP_INSTALLER=$(mktemp)
    trap 'rm -f "$STARSHIP_INSTALLER"' EXIT
    curl -fsSL --retry 3 --retry-all-errors -o "$STARSHIP_INSTALLER" \
        https://starship.rs/install.sh
    sh "$STARSHIP_INSTALLER" --yes --bin-dir "$USER_BIN"
    rm -f "$STARSHIP_INSTALLER"
    trap - EXIT
    echo "✅ Starship installed ($(starship --version | head -1))"
fi

configure_posix_shell() {
    local rc_file="$1"
    local shell_name="$2"
    local marker="# Starship prompt (added by starship.sh)"

    touch "$rc_file"
    if grep -q "starship init $shell_name" "$rc_file"; then
        echo "✅ Starship already configured for $shell_name"
        return
    fi

    {
        echo ""
        echo "$marker"
        # Keep these expansions literal so they run when the shell starts.
        # shellcheck disable=SC2016
        echo '[ -d "$HOME/.local/bin" ] && case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) export PATH="$HOME/.local/bin:$PATH";; esac'
        echo "command -v starship >/dev/null 2>&1 && eval \"\$(starship init $shell_name)\""
    } >> "$rc_file"
    echo "✅ Configured Starship for $shell_name in $rc_file"
}

configure_fish() {
    local config_file="$HOME/.config/fish/config.fish"
    mkdir -p "$(dirname "$config_file")"
    touch "$config_file"
    if grep -q 'starship init fish' "$config_file"; then
        echo "✅ Starship already configured for fish"
        return
    fi

    {
        echo ""
        echo "# Starship prompt (added by starship.sh)"
        # Fish expands HOME when it loads the generated config.
        # shellcheck disable=SC2016
        echo 'fish_add_path "$HOME/.local/bin"'
        echo 'type -q starship; and starship init fish | source'
    } >> "$config_file"
    echo "✅ Configured Starship for fish in $config_file"
}

# Bash is present on every supported Ubuntu install. Configure optional shells
# only when installed or already used by the current account.
configure_posix_shell "$HOME/.bashrc" bash
if command -v zsh &>/dev/null || [ -f "$HOME/.zshrc" ]; then
    configure_posix_shell "$HOME/.zshrc" zsh
fi
if command -v fish &>/dev/null || [ -f "$HOME/.config/fish/config.fish" ]; then
    configure_fish
fi

echo "✅ Starship setup complete!"
echo "💡 Open a new terminal to activate the prompt"
