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

echo "🚀 Installing Hugging Face CLI..."

find_hf() {
    if command -v hf &>/dev/null; then
        command -v hf
    elif [ -x "$HOME/.local/bin/hf" ]; then
        printf '%s\n' "$HOME/.local/bin/hf"
    else
        return 1
    fi
}

if HF_BIN=$(find_hf); then
    echo "✅ Hugging Face CLI already installed ($("$HF_BIN" version 2>/dev/null || echo 'version unknown'))"
    exit 0
fi

if ! command -v python3 &>/dev/null || ! dpkg -s python3-venv &>/dev/null; then
    echo "📦 Installing Python venv support required by the Hugging Face installer..."
    sudo apt-get update
    sudo apt-get install -y python3 python3-venv
fi

echo "📦 Downloading the official Hugging Face CLI installer..."
HF_INSTALLER=$(mktemp)
trap 'rm -f "$HF_INSTALLER"' EXIT
curl -fsSL --retry 3 --retry-all-errors \
    -o "$HF_INSTALLER" https://hf.co/cli/install.sh
bash "$HF_INSTALLER" --exclude-skill
rm -f "$HF_INSTALLER"
trap - EXIT

if ! HF_BIN=$(find_hf); then
    echo "❌ Hugging Face CLI installation failed or 'hf' is not in PATH" >&2
    exit 1
fi

echo "✅ Hugging Face CLI installed successfully ($("$HF_BIN" version 2>/dev/null || echo 'version unknown'))"
echo "💡 Run 'hf auth login' only if you need private or gated repositories"
