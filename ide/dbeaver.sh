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

echo "🚀 Installing DBeaver Community..."

# dev/databases.sh only installs CLI clients (psql/mysql/redis-cli/sqlite3 +
# pgcli/mycli/litecli) — this is the GUI counterpart.
if command -v dbeaver-ce &>/dev/null; then
    echo "✅ DBeaver already installed ($(dbeaver-ce -version 2>/dev/null | head -1 || echo 'version unknown'))"
    exit 0
fi

GPG_TMP=$(mktemp --suffix=.gpg)
trap 'rm -f "$GPG_TMP"' EXIT

echo "📦 Adding DBeaver GPG key and repository..."
sudo apt-get update
sudo apt-get install -y wget gpg

wget --tries=3 --waitretry=2 -qO- https://dbeaver.io/debs/dbeaver.gpg.key | gpg --dearmor > "$GPG_TMP"
sudo install -D -o root -g root -m 644 "$GPG_TMP" /etc/apt/keyrings/dbeaver.gpg

if [ ! -f /etc/apt/sources.list.d/dbeaver.list ]; then
    echo "deb [signed-by=/etc/apt/keyrings/dbeaver.gpg] https://dbeaver.io/debs/dbeaver-ce /" \
        | sudo tee /etc/apt/sources.list.d/dbeaver.list > /dev/null
fi

echo "📦 Installing dbeaver-ce..."
sudo apt-get update
sudo apt-get install -y dbeaver-ce

if command -v dbeaver-ce &>/dev/null; then
    echo "✅ DBeaver installed ($(dbeaver-ce -version 2>/dev/null | head -1 || echo 'version unknown'))"
else
    echo "❌ DBeaver installation failed"
    exit 1
fi

echo ""
echo "💡 Launch from the application menu, or run: dbeaver-ce"
echo "💡 Connect it to anything dev/databases.sh set up (Postgres, MySQL, Redis, SQLite)"
