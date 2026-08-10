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

echo "🚀 Installing Fabric..."

PROFILE_FILE="$HOME/.profile"
FABRIC_BIN="$HOME/.local/bin/fabric"

ensure_local_bin_path() {
    local marker="# ~/.local/bin (added by fabric.sh)"
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

if command -v fabric &>/dev/null; then
    ensure_local_bin_path
    echo "✅ Fabric already installed ($(fabric --version 2>/dev/null || echo 'version unknown'))"
    exit 0
fi
if [ -x "$FABRIC_BIN" ]; then
    ensure_local_bin_path
    echo "✅ Fabric already installed ($("$FABRIC_BIN" --version 2>/dev/null || echo 'version unknown'))"
    exit 0
fi

echo "📦 Downloading the official Fabric installer..."
FABRIC_INSTALLER=$(mktemp)
trap 'rm -f "$FABRIC_INSTALLER"' EXIT
curl -fsSL --retry 3 --retry-all-errors \
    -o "$FABRIC_INSTALLER" \
    https://raw.githubusercontent.com/danielmiessler/Fabric/main/scripts/installer/install.sh
PATH="$HOME/.local/bin:$PATH" bash "$FABRIC_INSTALLER"
rm -f "$FABRIC_INSTALLER"
trap - EXIT

if [ ! -x "$FABRIC_BIN" ] && ! command -v fabric &>/dev/null; then
    echo "❌ Fabric installation failed or 'fabric' is not in PATH" >&2
    exit 1
fi

ensure_local_bin_path
echo "✅ Fabric installed successfully"
echo "💡 Run 'fabric --setup' when you are ready to configure providers and patterns"
