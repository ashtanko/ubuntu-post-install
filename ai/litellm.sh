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

echo "🚀 Installing LiteLLM proxy CLI..."

LITELLM_VERSION="${LITELLM_VERSION:-latest}"
PROFILE_FILE="$HOME/.profile"
LITELLM_BIN="$HOME/.local/bin/litellm"
PIPX_BIN=""

ensure_local_bin_path() {
    local marker="# ~/.local/bin (added by litellm.sh)"
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

align_latest_proxy_dependencies() {
    [ "$LITELLM_VERSION" = "latest" ] || return 0
    if [ -z "$PIPX_BIN" ]; then
        PIPX_BIN=$(command -v pipx 2>/dev/null || true)
    fi
    if [ -z "$PIPX_BIN" ]; then
        echo "❌ pipx is required to repair LiteLLM's proxy dependencies" >&2
        return 1
    fi
    "$PIPX_BIN" runpip litellm install --upgrade \
        'fastapi>=0.136.3,<1.0' \
        'starlette>=1.0.1,<2.0'
}

if command -v litellm &>/dev/null; then
    ensure_local_bin_path
    if ! litellm --help >/dev/null 2>&1; then
        echo "🔧 Repairing the existing LiteLLM proxy dependency set..."
        align_latest_proxy_dependencies
        litellm --help >/dev/null || { echo "❌ Existing LiteLLM CLI could not start" >&2; exit 1; }
    fi
    echo "✅ LiteLLM already installed"
    exit 0
fi
if [ -x "$LITELLM_BIN" ]; then
    ensure_local_bin_path
    if ! "$LITELLM_BIN" --help >/dev/null 2>&1; then
        echo "🔧 Repairing the existing LiteLLM proxy dependency set..."
        align_latest_proxy_dependencies
        "$LITELLM_BIN" --help >/dev/null || { echo "❌ Existing LiteLLM CLI could not start" >&2; exit 1; }
    fi
    echo "✅ LiteLLM already installed"
    exit 0
fi

if ! command -v pipx &>/dev/null; then
    echo "📦 Installing pipx and Python venv support..."
    sudo apt-get update
    sudo apt-get install -y python3 python3-venv pipx
fi

LITELLM_PACKAGE="litellm[proxy]"
if [ "$LITELLM_VERSION" != "latest" ]; then
    LITELLM_PACKAGE="litellm[proxy]==$LITELLM_VERSION"
fi

echo "📦 Installing $LITELLM_PACKAGE in an isolated pipx environment..."
PIPX_BIN=$(command -v pipx)
"$PIPX_BIN" install "$LITELLM_PACKAGE"

# LiteLLM's latest proxy release can resolve an older FastAPI/Starlette pair
# that no longer exposes APIs imported by the proxy. Keep latest installs on
# the compatibility range published by LiteLLM's current upstream project.
# Explicitly pinned LiteLLM releases retain their own dependency constraints.
if [ "$LITELLM_VERSION" = "latest" ]; then
    align_latest_proxy_dependencies
fi

if [ ! -x "$LITELLM_BIN" ] && ! command -v litellm &>/dev/null; then
    echo "❌ LiteLLM installation failed or 'litellm' is not in PATH" >&2
    exit 1
fi

if ! "$LITELLM_BIN" --help >/dev/null; then
    echo "❌ LiteLLM was installed but its CLI could not start" >&2
    exit 1
fi

ensure_local_bin_path
echo "✅ LiteLLM proxy CLI installed successfully"
echo "💡 Start with 'litellm --model ollama/<model>' or provide a config file with --config"
