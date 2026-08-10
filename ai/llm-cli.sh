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

echo "🚀 Installing LLM CLI..."

LLM_VERSION="${LLM_VERSION:-latest}"
PROFILE_FILE="$HOME/.profile"
LLM_BIN="$HOME/.local/bin/llm"

ensure_local_bin_path() {
    local marker="# ~/.local/bin (added by llm-cli.sh)"
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

if command -v llm &>/dev/null; then
    ensure_local_bin_path
    echo "✅ LLM CLI already installed ($(llm --version 2>/dev/null || echo 'version unknown'))"
    exit 0
fi
if [ -x "$LLM_BIN" ]; then
    ensure_local_bin_path
    echo "✅ LLM CLI already installed ($("$LLM_BIN" --version 2>/dev/null || echo 'version unknown'))"
    exit 0
fi

if ! command -v pipx &>/dev/null; then
    echo "📦 Installing pipx and Python venv support..."
    sudo apt-get update
    sudo apt-get install -y python3 python3-venv pipx
fi

LLM_PACKAGE="llm"
if [ "$LLM_VERSION" != "latest" ]; then
    LLM_PACKAGE="llm==$LLM_VERSION"
fi

echo "📦 Installing $LLM_PACKAGE in an isolated pipx environment..."
PIPX_BIN=$(command -v pipx)
"$PIPX_BIN" install "$LLM_PACKAGE"

if [ ! -x "$LLM_BIN" ] && ! command -v llm &>/dev/null; then
    echo "❌ LLM CLI installation failed or 'llm' is not in PATH" >&2
    exit 1
fi

ensure_local_bin_path
echo "✅ LLM CLI installed successfully"
echo "💡 Add providers with commands such as 'llm install llm-ollama' or 'llm install llm-anthropic'"
