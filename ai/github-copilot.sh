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

echo "🚀 Installing GitHub Copilot CLI..."

COPILOT_VERSION="${COPILOT_VERSION:-latest}"
COPILOT_PREFIX="$HOME/.local"
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

ensure_copilot_path() {
    local marker="# ~/.local/bin (added by github-copilot.sh)"
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

find_copilot() {
    if command -v copilot &>/dev/null; then
        command -v copilot
    elif [ -x "$COPILOT_PREFIX/bin/copilot" ]; then
        printf '%s\n' "$COPILOT_PREFIX/bin/copilot"
    else
        return 1
    fi
}

if COPILOT_BIN=$(find_copilot); then
    ensure_copilot_path
    echo "✅ GitHub Copilot CLI already installed ($("$COPILOT_BIN" version 2>/dev/null || echo 'version unknown'))"
    exit 0
fi

echo "📦 Downloading the official GitHub Copilot CLI installer..."
COPILOT_INSTALLER=$(mktemp)
trap 'rm -f "$COPILOT_INSTALLER"' EXIT
curl -fsSL --retry 3 --retry-all-errors \
    -o "$COPILOT_INSTALLER" https://gh.io/copilot-install

PATH="$COPILOT_PREFIX/bin:$PATH" PREFIX="$COPILOT_PREFIX" VERSION="$COPILOT_VERSION" \
    bash "$COPILOT_INSTALLER"
rm -f "$COPILOT_INSTALLER"
trap - EXIT

if ! COPILOT_BIN=$(find_copilot); then
    echo "❌ GitHub Copilot CLI installation failed or 'copilot' is not in PATH" >&2
    exit 1
fi

ensure_copilot_path
echo "✅ GitHub Copilot CLI installed successfully ($("$COPILOT_BIN" version 2>/dev/null || echo 'version unknown'))"
echo "💡 Next step: run 'copilot', enter /login, and follow the browser prompts"
