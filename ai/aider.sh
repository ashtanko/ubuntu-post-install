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

echo "🚀 Installing Aider..."

PROFILE_FILE="$HOME/.profile"

has_local_bin_path() {
    local line
    [ -f "$PROFILE_FILE" ] || return 1
    while IFS= read -r line; do
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        if [[ "$line" == *"\$HOME/.local/bin"* || "$line" == *"\${HOME}/.local/bin"* ]]; then
            return 0
        fi
    done < "$PROFILE_FILE"
    return 1
}

ensure_aider_path() {
    local marker="# ~/.local/bin (added by aider.sh)"
    # shellcheck disable=SC2016
    local path_line='[ -d "$HOME/.local/bin" ] && case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) export PATH="$HOME/.local/bin:$PATH";; esac'
    if { [ -f "$PROFILE_FILE" ] && grep -qF "$marker" "$PROFILE_FILE"; } \
        || has_local_bin_path; then
        return
    fi
    {
        echo ""
        echo "$marker"
        echo "$path_line"
    } >> "$PROFILE_FILE"
    echo "✅ Added \$HOME/.local/bin to PATH in $PROFILE_FILE"
}

find_aider() {
    if command -v aider &>/dev/null; then
        command -v aider
    elif [ -x "$HOME/.local/bin/aider" ]; then
        printf '%s\n' "$HOME/.local/bin/aider"
    else
        return 1
    fi
}

if AIDER_BIN=$(find_aider); then
    ensure_aider_path
    echo "✅ Aider already installed ($("$AIDER_BIN" --version 2>/dev/null || echo 'version unknown'))"
    exit 0
fi

echo "📦 Downloading the official Aider installer..."
AIDER_INSTALLER=$(mktemp)
trap 'rm -f "$AIDER_INSTALLER"' EXIT
curl -fsSL --retry 3 --retry-all-errors \
    -o "$AIDER_INSTALLER" https://aider.chat/install.sh
PATH="$HOME/.local/bin:$PATH" sh "$AIDER_INSTALLER"
rm -f "$AIDER_INSTALLER"
trap - EXIT

if ! AIDER_BIN=$(find_aider); then
    echo "❌ Aider installation failed or 'aider' is not in PATH" >&2
    exit 1
fi

ensure_aider_path
echo "✅ Aider installed successfully ($("$AIDER_BIN" --version 2>/dev/null || echo 'version unknown'))"
echo "💡 Configure a provider API key or use Aider with a local Ollama model"
