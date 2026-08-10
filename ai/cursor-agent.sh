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

echo "🚀 Installing Cursor Agent CLI..."

PROFILE_FILE="$HOME/.profile"
CURSOR_AGENT_BIN="$HOME/.local/bin/cursor-agent"

ensure_local_bin_path() {
    local marker="# ~/.local/bin (added by cursor-agent.sh)"
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

if command -v cursor-agent &>/dev/null; then
    ensure_local_bin_path
    echo "✅ Cursor Agent already installed ($(cursor-agent --version 2>/dev/null || echo 'version unknown'))"
    exit 0
fi
if [ -x "$CURSOR_AGENT_BIN" ]; then
    ensure_local_bin_path
    echo "✅ Cursor Agent already installed ($("$CURSOR_AGENT_BIN" --version 2>/dev/null || echo 'version unknown'))"
    exit 0
fi

echo "📦 Downloading the official Cursor Agent installer..."
CURSOR_INSTALLER=$(mktemp)
trap 'rm -f "$CURSOR_INSTALLER"' EXIT
curl -fsSL --retry 3 --retry-all-errors -o "$CURSOR_INSTALLER" https://cursor.com/install
PATH="$HOME/.local/bin:$PATH" bash "$CURSOR_INSTALLER"
rm -f "$CURSOR_INSTALLER"
trap - EXIT

if [ ! -x "$CURSOR_AGENT_BIN" ] && ! command -v cursor-agent &>/dev/null; then
    echo "❌ Cursor Agent installation failed or 'cursor-agent' is not in PATH" >&2
    exit 1
fi

ensure_local_bin_path
echo "✅ Cursor Agent installed successfully"
echo "💡 Run 'cursor-agent' to authenticate and start a session"
