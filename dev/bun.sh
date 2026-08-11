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

echo "🚀 Installing Bun..."

BUN_DIR="${BUN_INSTALL:-$HOME/.bun}"
BUN_BIN="$BUN_DIR/bin/bun"

if [ -x "$BUN_BIN" ]; then
    echo "✅ Bun already installed ($("$BUN_BIN" --version 2>/dev/null | head -1))"
    echo "💡 Update with: bun upgrade"
    exit 0
fi

if ! command -v unzip &>/dev/null; then
    echo "📦 Installing unzip (required by the Bun installer)..."
    sudo apt-get update
    sudo apt-get install -y unzip
fi

echo "📥 Downloading and running the official Bun installer..."
BUN_INSTALLER=$(mktemp)
trap 'rm -f "$BUN_INSTALLER"' EXIT
curl -fsSL --retry 3 --retry-all-errors -o "$BUN_INSTALLER" https://bun.sh/install
BUN_INSTALL="$BUN_DIR" bash "$BUN_INSTALLER"
rm -f "$BUN_INSTALLER"
trap - EXIT

if [ ! -x "$BUN_BIN" ]; then
    echo "❌ Bun installation failed"
    exit 1
fi

# Persist PATH in shell configs
# shellcheck disable=SC2016
BUN_PATH_LINE='export BUN_INSTALL="'"$BUN_DIR"'"
export PATH="$BUN_INSTALL/bin:$PATH"'
for RC in "$HOME/.zshrc" "$HOME/.bashrc"; do
    if [ -f "$RC" ] && ! grep -q 'BUN_INSTALL' "$RC"; then
        {
            echo ""
            echo "# Bun"
            printf '%s\n' "$BUN_PATH_LINE"
        } >> "$RC"
        echo "✅ Added Bun to PATH in $RC"
    fi
done

export BUN_INSTALL="$BUN_DIR"
export PATH="$BUN_INSTALL/bin:$PATH"

echo ""
echo "✅ Bun installed!"
echo "   $(bun --version | head -1)"
echo "💡 Reload your shell or run: source ~/.zshrc"
