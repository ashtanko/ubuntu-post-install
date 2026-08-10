#!/bin/bash
set -euo pipefail

if [ -z "${BASH_VERSION:-}" ]; then
    exec /bin/bash "$0" "$@"
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_HELPER="$REPO_ROOT/lib/config.bash"
# shellcheck source=lib/config.bash
source "$CONFIG_HELPER" || { echo "❌ Missing config helper: $CONFIG_HELPER" >&2; exit 1; }
load_config "$REPO_ROOT"

echo "🚀 Installing Mistral Vibe CLI..."

PROFILE_FILE="$HOME/.profile"
VIBE_BIN="$HOME/.local/bin/vibe"

ensure_local_bin_path() {
    local marker="# ~/.local/bin (added by mistral-vibe.sh)"
    # shellcheck disable=SC2016
    local path_line='[ -d "$HOME/.local/bin" ] && case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) export PATH="$HOME/.local/bin:$PATH";; esac'
    if { [ -f "$PROFILE_FILE" ] && grep -qF "$marker" "$PROFILE_FILE"; } \
        || { [ -f "$PROFILE_FILE" ] && grep -Eq '^[^#]*PATH=.*\$\{?HOME\}?/\.local/bin' "$PROFILE_FILE"; }; then
        return
    fi
    {
        echo ""
        echo "$marker"
        echo "$path_line"
    } >> "$PROFILE_FILE"
    echo "✅ Added \$HOME/.local/bin to PATH in $PROFILE_FILE"
}

if command -v vibe &>/dev/null; then
    ensure_local_bin_path
    echo "✅ Mistral Vibe already installed ($(vibe --version 2>/dev/null || echo 'version unknown'))"
    exit 0
fi
if [ -x "$VIBE_BIN" ]; then
    ensure_local_bin_path
    echo "✅ Mistral Vibe already installed ($("$VIBE_BIN" --version 2>/dev/null || echo 'version unknown'))"
    exit 0
fi

echo "📦 Downloading the official Mistral Vibe installer..."
VIBE_INSTALLER=$(mktemp)
trap 'rm -f "$VIBE_INSTALLER"' EXIT
curl -fsSL --retry 3 --retry-all-errors -o "$VIBE_INSTALLER" https://mistral.ai/vibe/install.sh
PATH="$HOME/.local/bin:$PATH" bash "$VIBE_INSTALLER"
rm -f "$VIBE_INSTALLER"
trap - EXIT

if [ ! -x "$VIBE_BIN" ] && ! command -v vibe &>/dev/null; then
    echo "❌ Mistral Vibe installation failed or 'vibe' is not in PATH" >&2
    exit 1
fi

ensure_local_bin_path
echo "✅ Mistral Vibe installed successfully"
echo "💡 Run 'vibe' to configure Mistral, a local model, or an OpenAI-compatible provider"
