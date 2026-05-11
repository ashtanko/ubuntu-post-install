#!/bin/bash
set -euo pipefail

# Re-exec under bash if invoked via `sh` (dash mishandles &>, [[ ]], etc.)
if [ -z "${BASH_VERSION:-}" ]; then
    exec /bin/bash "$0" "$@"
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ -f "$REPO_ROOT/.env" ]] && { set -a; source "$REPO_ROOT/.env"; set +a; }

echo "🚀 Installing CodeRabbit CLI..."

if command -v coderabbit &>/dev/null; then
    echo "✅ CodeRabbit CLI already installed ($(coderabbit --version 2>/dev/null || echo 'version unknown'))"
    exit 0
fi

echo "📦 Downloading and running CodeRabbit installer..."
curl -fsSL https://cli.coderabbit.ai/install.sh | bash

# Installer writes a PATH entry into ~/.zshrc / ~/.bashrc but doesn't
# affect the *current* shell — re-resolve via common install locations.
FOUND=0
if ! command -v coderabbit &>/dev/null; then
    for CANDIDATE in "$HOME/.local/bin/coderabbit" "$HOME/.coderabbit/bin/coderabbit"; do
        if [ -x "$CANDIDATE" ]; then
            echo "✅ CodeRabbit CLI installed at $CANDIDATE"
            FOUND=1
            break
        fi
    done
fi

if command -v coderabbit &>/dev/null || [ "$FOUND" = "1" ]; then
    echo "✅ CodeRabbit CLI installed successfully!"
    echo "💡 Reload your shell or run: source ~/.zshrc"
    echo "💡 Next step: run 'coderabbit auth login' to authenticate"
else
    echo "❌ CodeRabbit CLI installation failed"
    exit 1
fi
