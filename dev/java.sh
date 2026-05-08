#!/bin/bash
set -euo pipefail

# Re-exec under bash if invoked via `sh` (dash mishandles &>, [[ ]], etc.)
if [ -z "${BASH_VERSION:-}" ]; then
    exec /bin/bash "$0" "$@"
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ -f "$REPO_ROOT/.env" ]] && { set -a; source "$REPO_ROOT/.env"; set +a; }

echo "🚀 Installing Java (OpenJDK)..."

if command -v java &>/dev/null; then
    echo "✅ Java already installed"
    java -version
    exit 0
fi

echo "📦 Updating package lists..."
sudo apt update -y

echo "📦 Installing default JDK..."
sudo apt install -y default-jdk

if command -v java &>/dev/null; then
    echo "✅ Java installed successfully"
    java -version
else
    echo "❌ Java installation failed"
    exit 1
fi
