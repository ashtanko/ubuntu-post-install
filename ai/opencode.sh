#!/bin/bash
set -euo pipefail

# Re-exec under bash if invoked via `sh` (dash mishandles &>, [[ ]], etc.)
if [ -z "${BASH_VERSION:-}" ]; then
    exec /bin/bash "$0" "$@"
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[ -f "$REPO_ROOT/.env" ] && { set -a; . "$REPO_ROOT/.env"; set +a; }

echo "🚀 Installing opencode..."

OPENCODE_BIN="${OPENCODE_INSTALL_DIR:-$HOME/.opencode/bin}/opencode"

if [ -x "$OPENCODE_BIN" ] && "$OPENCODE_BIN" --version 2>/dev/null | grep -qi "opencode"; then
    echo "✅ opencode already installed ($("$OPENCODE_BIN" --version 2>/dev/null))"
    exit 0
fi

echo "📦 Downloading and running opencode installer..."
curl -fsSL https://opencode.ai/install | bash

if [ -x "$OPENCODE_BIN" ]; then
    echo "✅ opencode installed successfully!"
    echo "💡 Add to PATH: export PATH=\"\$HOME/.opencode/bin:\$PATH\""
else
    echo "❌ opencode installation failed"
    exit 1
fi

# Persist opencode bin in shell configs.
# Single quotes are intentional — `$HOME` / `$PATH` must be literal in the rc file.
# shellcheck disable=SC2016
OPENCODE_PATH_LINE='export PATH="$HOME/.opencode/bin:$PATH"'
for RC in "$HOME/.zshrc" "$HOME/.bashrc"; do
    if [ -f "$RC" ] && ! grep -q '.opencode/bin' "$RC"; then
        {
            echo ""
            echo "# opencode"
            echo "$OPENCODE_PATH_LINE"
        } >> "$RC"
        echo "✅ Added opencode to PATH in $RC"
    fi
done

echo "💡 Reload your shell or run: source ~/.zshrc"
