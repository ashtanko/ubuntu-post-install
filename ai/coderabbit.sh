#!/bin/bash
set -euo pipefail

# Re-exec under bash if invoked via `sh` (dash mishandles &>, [[ ]], etc.)
if [ -z "${BASH_VERSION:-}" ]; then
    exec /bin/bash "$0" "$@"
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ -f "$REPO_ROOT/.env" ]] && { set -a; source "$REPO_ROOT/.env"; set +a; }

echo "🚀 Installing CodeRabbit CLI..."

# Upstream installer hard-codes ~/.local/bin unless CODERABBIT_INSTALL_DIR is set.
CODERABBIT_BIN="${CODERABBIT_INSTALL_DIR:-$HOME/.local/bin}/coderabbit"

if [ -x "$CODERABBIT_BIN" ]; then
    echo "✅ CodeRabbit CLI already installed ($("$CODERABBIT_BIN" --version 2>/dev/null || echo 'version unknown'))"
    exit 0
fi

echo "📦 Downloading and running CodeRabbit installer..."
curl -fsSL https://cli.coderabbit.ai/install.sh | bash

if [ -x "$CODERABBIT_BIN" ]; then
    echo "✅ CodeRabbit CLI installed successfully!"
    echo "💡 Reload your shell or run: source ~/.zshrc"
    echo "💡 Next step: run 'coderabbit auth login' to authenticate"
else
    echo "❌ CodeRabbit CLI installation failed"
    exit 1
fi
