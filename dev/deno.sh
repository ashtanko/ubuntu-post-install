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

echo "🚀 Installing Deno..."

DENO_DIR="${DENO_INSTALL:-$HOME/.deno}"
DENO_BIN="$DENO_DIR/bin/deno"

if [ -x "$DENO_BIN" ]; then
    echo "✅ Deno already installed ($("$DENO_BIN" --version 2>/dev/null | head -1))"
    echo "💡 Update with: deno upgrade"
    exit 0
fi

if ! command -v unzip &>/dev/null; then
    echo "📦 Installing unzip (required by the Deno installer)..."
    sudo apt-get update
    sudo apt-get install -y unzip
fi

echo "📥 Downloading and running the official Deno installer..."
DENO_INSTALLER=$(mktemp)
trap 'rm -f "$DENO_INSTALLER"' EXIT
curl -fsSL --retry 3 --retry-all-errors -o "$DENO_INSTALLER" https://deno.land/install.sh
DENO_INSTALL="$DENO_DIR" sh "$DENO_INSTALLER"
rm -f "$DENO_INSTALLER"
trap - EXIT

if [ ! -x "$DENO_BIN" ]; then
    echo "❌ Deno installation failed"
    exit 1
fi

# Persist PATH in shell configs
# shellcheck disable=SC2016
DENO_PATH_LINE='export DENO_INSTALL="'"$DENO_DIR"'"
export PATH="$DENO_INSTALL/bin:$PATH"'
for RC in "$HOME/.zshrc" "$HOME/.bashrc"; do
    if [ -f "$RC" ] && ! grep -q 'DENO_INSTALL' "$RC"; then
        {
            echo ""
            echo "# Deno"
            printf '%s\n' "$DENO_PATH_LINE"
        } >> "$RC"
        echo "✅ Added Deno to PATH in $RC"
    fi
done

export DENO_INSTALL="$DENO_DIR"
export PATH="$DENO_INSTALL/bin:$PATH"

echo ""
echo "✅ Deno installed!"
echo "   $(deno --version | head -1)"
echo "💡 Reload your shell or run: source ~/.zshrc"
