#!/bin/bash
set -euo pipefail

# Re-exec under bash if invoked via `sh` (dash mishandles &>, [[ ]], etc.)
if [ -z "${BASH_VERSION:-}" ]; then
    exec /bin/bash "$0" "$@"
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ -f "$REPO_ROOT/.env" ]] && { set -a; source "$REPO_ROOT/.env"; set +a; }

echo "🚀 Installing database CLI clients..."

install_if_missing() {
    local cmd="$1"
    local pkg="$2"
    if command -v "$cmd" &>/dev/null; then
        echo "✅ $cmd already installed"
    else
        echo "📦 Installing $pkg..."
        sudo apt-get install -y "$pkg"
    fi
}

sudo apt-get update

# Native clients
install_if_missing psql    postgresql-client
install_if_missing redis-cli redis-tools
install_if_missing mysql   default-mysql-client
install_if_missing sqlite3 sqlite3

# Interactive shells via pipx (auto-completion + syntax highlighting)
if ! command -v pipx &>/dev/null; then
    echo "📦 Installing pipx..."
    sudo apt-get install -y pipx
    pipx ensurepath >/dev/null 2>&1 || true
fi

for tool in pgcli mycli litecli; do
    if command -v "$tool" &>/dev/null; then
        echo "✅ $tool already installed"
    else
        echo "📦 Installing $tool via pipx..."
        pipx install "$tool"
    fi
done

echo ""
echo "✅ Database CLI clients installed!"
echo "   psql      - PostgreSQL"
echo "   redis-cli - Redis"
echo "   mysql     - MySQL/MariaDB"
echo "   sqlite3   - SQLite"
echo "   pgcli     - PostgreSQL with autocomplete"
echo "   mycli     - MySQL with autocomplete"
echo "   litecli   - SQLite with autocomplete"
