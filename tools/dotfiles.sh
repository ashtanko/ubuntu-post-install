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

echo "🚀 Installing chezmoi (dotfiles manager)..."

USER_BIN="$HOME/.local/bin"
mkdir -p "$USER_BIN"
export PATH="$USER_BIN:$PATH"

if command -v chezmoi &>/dev/null; then
    echo "✅ chezmoi already installed ($(chezmoi --version | head -1))"
else
    if ! command -v curl &>/dev/null; then
        echo "📦 Installing curl..."
        sudo apt-get update
        sudo apt-get install -y curl
    fi
    echo "📦 Installing chezmoi to $USER_BIN..."
    CHEZMOI_INSTALLER=$(mktemp)
    trap 'rm -f "$CHEZMOI_INSTALLER"' EXIT
    curl -fsSL --retry 3 --retry-all-errors -o "$CHEZMOI_INSTALLER" https://get.chezmoi.io
    # No "--" here: chezmoi's docs use it to separate `sh -c "..."`'s own
    # implicit $0 from the install script's args, but we're already invoking
    # the saved file directly, so `-b` must be $1 or the installer's getopts
    # never sees it (and silently falls through to running plain `chezmoi -b`).
    sh "$CHEZMOI_INSTALLER" -b "$USER_BIN"
    rm -f "$CHEZMOI_INSTALLER"
    trap - EXIT

    if ! command -v chezmoi &>/dev/null; then
        echo "❌ chezmoi installation failed or is not in PATH"
        exit 1
    fi
    echo "✅ chezmoi installed ($(chezmoi --version | head -1))"
fi

# Persist ~/.local/bin on PATH (several other scripts already add this same
# guarded line; grep -q keeps it a no-op if one of them got here first).
# shellcheck disable=SC2016
PATH_LINE='[ -d "$HOME/.local/bin" ] && case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) export PATH="$HOME/.local/bin:$PATH";; esac'
for RC in "$HOME/.zshrc" "$HOME/.bashrc"; do
    [ -f "$RC" ] || continue
    # shellcheck disable=SC2016
    grep -qF '$HOME/.local/bin' "$RC" || echo "$PATH_LINE" >> "$RC"
done

# Optional: point an existing source-of-truth repo at chezmoi. `chezmoi init`
# only clones into ~/.local/share/chezmoi — it never touches target files —
# so this is safe to run unattended. Deliberately NOT running `--apply` here:
# that overwrites files in $HOME, and doing that without the user reviewing
# `chezmoi diff` first is the kind of surprise this toolkit avoids.
if [ -n "${DOTFILES_REPO:-}" ]; then
    if [ -d "$HOME/.local/share/chezmoi/.git" ]; then
        echo "✅ chezmoi source directory already initialized"
    else
        echo "📥 Initializing chezmoi from $DOTFILES_REPO..."
        chezmoi init "$DOTFILES_REPO"
        echo "✅ Source directory ready: ~/.local/share/chezmoi"
    fi
fi

echo ""
echo "✅ chezmoi ready!"
if [ -z "${DOTFILES_REPO:-}" ]; then
    echo "💡 Start tracking a file:   chezmoi add ~/.zshrc"
    echo "💡 Or pull an existing repo: DOTFILES_REPO=<url> bash tools/dotfiles.sh"
else
    echo "💡 Review before applying: chezmoi diff"
    echo "💡 Apply when ready:       chezmoi apply"
fi
