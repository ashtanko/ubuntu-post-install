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

echo "🚀 Installing goose CLI..."

PROFILE_FILE="$HOME/.profile"
GOOSE_BIN="$HOME/.local/bin/goose"

ensure_local_bin_path() {
    local marker="# ~/.local/bin (added by goose.sh)"
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

if command -v goose &>/dev/null; then
    ensure_local_bin_path
    echo "✅ goose already installed ($(goose --version 2>/dev/null || echo 'version unknown'))"
    exit 0
fi
if [ -x "$GOOSE_BIN" ]; then
    ensure_local_bin_path
    echo "✅ goose already installed ($("$GOOSE_BIN" --version 2>/dev/null || echo 'version unknown'))"
    exit 0
fi

echo "📦 Downloading the official goose CLI installer..."
GOOSE_INSTALLER=$(mktemp)
trap 'rm -f "$GOOSE_INSTALLER"' EXIT
curl -fsSL --retry 3 --retry-all-errors \
    -o "$GOOSE_INSTALLER" \
    https://github.com/aaif-goose/goose/releases/download/stable/download_cli.sh
CONFIGURE=false PATH="$HOME/.local/bin:$PATH" bash "$GOOSE_INSTALLER"
rm -f "$GOOSE_INSTALLER"
trap - EXIT

if [ ! -x "$GOOSE_BIN" ] && ! command -v goose &>/dev/null; then
    echo "❌ goose installation failed or 'goose' is not in PATH" >&2
    exit 1
fi

ensure_local_bin_path
echo "✅ goose CLI installed successfully"
echo "💡 Run 'goose configure' when you are ready to select a model provider"
