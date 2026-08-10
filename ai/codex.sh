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

echo "🚀 Installing OpenAI Codex CLI..."

CODEX_RELEASE="${CODEX_RELEASE:-latest}"

find_codex() {
    if command -v codex &>/dev/null; then
        command -v codex
    elif [ -x "$HOME/.local/bin/codex" ]; then
        printf '%s\n' "$HOME/.local/bin/codex"
    else
        return 1
    fi
}

if CODEX_BIN=$(find_codex); then
    echo "✅ Codex already installed ($("$CODEX_BIN" --version 2>/dev/null || echo 'version unknown'))"
    exit 0
fi

echo "📦 Downloading the official Codex installer..."
CODEX_INSTALLER=$(mktemp)
trap 'rm -f "$CODEX_INSTALLER"' EXIT
curl -fsSL --retry 3 --retry-all-errors \
    -o "$CODEX_INSTALLER" https://chatgpt.com/codex/install.sh

CODEX_RELEASE="$CODEX_RELEASE" CODEX_NON_INTERACTIVE=true sh "$CODEX_INSTALLER"
rm -f "$CODEX_INSTALLER"
trap - EXIT

if ! CODEX_BIN=$(find_codex); then
    echo "❌ Codex installation failed or 'codex' is not in PATH" >&2
    exit 1
fi

echo "✅ Codex installed successfully ($("$CODEX_BIN" --version 2>/dev/null || echo 'version unknown'))"
echo "💡 Next step: run 'codex' and choose Sign in with ChatGPT"
