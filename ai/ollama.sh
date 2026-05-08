#!/bin/bash
set -euo pipefail

# Re-exec under bash if invoked via `sh` (dash on Ubuntu mishandles &>, [[ ]], etc.)
if [ -z "${BASH_VERSION:-}" ]; then
    exec /bin/bash "$0" "$@"
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ -f "$REPO_ROOT/.env" ]] && { set -a; source "$REPO_ROOT/.env"; set +a; }

echo "🚀 Installing Ollama..."

if command -v ollama >/dev/null 2>&1; then
    echo "✅ Ollama already installed ($(ollama --version 2>/dev/null | head -1))"
    echo "💡 To upgrade, re-run: curl -fsSL https://ollama.com/install.sh | sh"
    exit 0
fi

# The official installer needs zstd to extract its tarball; minimal Ubuntu lacks it.
if ! command -v zstd &>/dev/null; then
    echo "📦 Installing zstd (required by the Ollama installer)..."
    sudo apt-get update
    sudo apt-get install -y zstd
fi

echo "📦 Downloading and running official Ollama installer..."
curl -fsSL https://ollama.com/install.sh | sh

if ! command -v ollama &>/dev/null; then
    echo "❌ Installation failed or 'ollama' is not in PATH"
    exit 1
fi

echo ""
echo "✅ Ollama installed successfully!"
echo "   $(ollama --version 2>/dev/null | head -1)"

# Ensure the systemd service is up (the installer sets it up on systemd hosts)
if command -v systemctl >/dev/null 2>&1 && systemctl list-unit-files | grep -q '^ollama.service'; then
    if systemctl is-active --quiet ollama; then
        echo "✅ ollama.service is running"
    else
        echo "📦 Starting ollama.service..."
        sudo systemctl enable --now ollama || true
    fi
fi

echo ""
echo "💡 Pull a model to get started, e.g.:"
echo "     ollama pull llama3.2"
echo "     ollama run llama3.2"
echo "💡 API is exposed on http://localhost:11434"
