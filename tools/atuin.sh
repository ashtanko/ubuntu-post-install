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

echo "🚀 Installing Atuin (searchable, syncable shell history)..."

# Works across all three shells this toolkit installs — zsh.sh, fish.sh, bash.
ATUIN_BIN=""
for CANDIDATE in "$(command -v atuin 2>/dev/null || true)" "$HOME/.atuin/bin/atuin" "$HOME/.local/bin/atuin"; do
    if [ -n "$CANDIDATE" ] && [ -x "$CANDIDATE" ]; then
        ATUIN_BIN="$CANDIDATE"
        break
    fi
done

if [ -n "$ATUIN_BIN" ]; then
    echo "✅ Atuin already installed ($("$ATUIN_BIN" --version 2>/dev/null | head -1))"
else
    if ! command -v curl &>/dev/null; then
        echo "📦 Installing curl..."
        sudo apt-get update
        sudo apt-get install -y curl
    fi

    echo "📦 Downloading and running the official Atuin installer..."
    ATUIN_INSTALLER=$(mktemp)
    trap 'rm -f "$ATUIN_INSTALLER"' EXIT
    curl -fsSL --retry 3 --retry-all-errors -o "$ATUIN_INSTALLER" https://setup.atuin.sh
    # The installer offers to edit shell rc files itself; this script does that
    # below with the repo's usual grep-guarded, idempotent approach instead.
    ATUIN_NO_MODIFY_PATH=1 sh "$ATUIN_INSTALLER" || true
    rm -f "$ATUIN_INSTALLER"
    trap - EXIT

    for CANDIDATE in "$(command -v atuin 2>/dev/null || true)" "$HOME/.atuin/bin/atuin" "$HOME/.local/bin/atuin"; do
        if [ -n "$CANDIDATE" ] && [ -x "$CANDIDATE" ]; then
            ATUIN_BIN="$CANDIDATE"
            break
        fi
    done

    if [ -z "$ATUIN_BIN" ]; then
        echo "❌ Atuin installation failed or the binary is not where expected"
        exit 1
    fi
    echo "✅ Atuin installed ($("$ATUIN_BIN" --version 2>/dev/null | head -1))"
fi

ATUIN_DIR="$(dirname "$ATUIN_BIN")"

# --- Shell integration (idempotent rc edits, same shape as modern-cli.sh) ---
# Zsh: works out of the box. Bash: needs bash-preexec, which Atuin's own
# installer places at ~/.bash-preexec.sh — source it before atuin init.
if [ -f "$HOME/.zshrc" ] && ! grep -q 'atuin init zsh' "$HOME/.zshrc"; then
    {
        echo ""
        echo "# Atuin"
        echo "export PATH=\"$ATUIN_DIR:\$PATH\""
        # shellcheck disable=SC2016
        echo 'eval "$(atuin init zsh)"'
    } >> "$HOME/.zshrc"
    echo "✅ Added Atuin init to ~/.zshrc"
fi

if [ -f "$HOME/.bashrc" ] && ! grep -q 'atuin init bash' "$HOME/.bashrc"; then
    {
        echo ""
        echo "# Atuin (bash-preexec is required and must be sourced first)"
        echo "export PATH=\"$ATUIN_DIR:\$PATH\""
        # shellcheck disable=SC2016
        echo '[[ -f "$HOME/.bash-preexec.sh" ]] && source "$HOME/.bash-preexec.sh"'
        # shellcheck disable=SC2016
        echo 'eval "$(atuin init bash)"'
    } >> "$HOME/.bashrc"
    echo "✅ Added Atuin init to ~/.bashrc"
fi

FISH_CONFIG="$HOME/.config/fish/config.fish"
if [ -f "$FISH_CONFIG" ] && ! grep -q 'atuin init fish' "$FISH_CONFIG"; then
    {
        echo ""
        echo "# Atuin"
        echo "fish_add_path $ATUIN_DIR"
        echo "atuin init fish | source"
    } >> "$FISH_CONFIG"
    echo "✅ Added Atuin init to $FISH_CONFIG"
fi

echo ""
echo "✅ Atuin ready!"
echo "💡 Reload your shell, then press ↑ or Ctrl-R for the new history search"
echo "💡 Import your existing history: atuin import auto"
echo "💡 History stays local by default. Optional end-to-end encrypted sync:"
echo "     atuin register -u <username> -e <email>   (then: atuin sync)"
