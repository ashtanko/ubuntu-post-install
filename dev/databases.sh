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

# MongoDB shell + tools. Not in Ubuntu's own archive — MongoDB publishes its
# own apt repo, pinned per Ubuntu codename. Newer codenames sometimes have no
# suite yet, so fall back to the most recent LTS that does (same approach as
# dev/terraform.sh).
if command -v mongosh &>/dev/null; then
    echo "✅ mongosh already installed"
else
    echo "📦 Adding MongoDB apt repository..."
    sudo apt-get install -y ca-certificates curl gnupg

    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL --retry 3 --retry-all-errors https://www.mongodb.org/static/pgp/server-8.0.asc \
        | sudo gpg --dearmor --yes -o /etc/apt/keyrings/mongodb-server-8.0.gpg
    sudo chmod a+r /etc/apt/keyrings/mongodb-server-8.0.gpg

    CODENAME=$(lsb_release -cs)
    MONGO_SUITE=""
    # No `curl | grep -q` here — grep exits at the first match, curl dies of
    # SIGPIPE, and `set -o pipefail` would fail the check for every suite.
    MONGO_INDEX=$(mktemp)
    # shellcheck disable=SC2064
    trap "rm -f '$MONGO_INDEX'" EXIT
    for CANDIDATE in "$CODENAME" noble jammy; do
        if curl -fsSL --retry 3 --retry-all-errors -o "$MONGO_INDEX" \
            "https://repo.mongodb.org/apt/ubuntu/dists/${CANDIDATE}/mongodb-org/8.0/Release" 2>/dev/null; then
            MONGO_SUITE="$CANDIDATE"
            break
        fi
    done
    rm -f "$MONGO_INDEX"
    trap - EXIT

    if [ -z "$MONGO_SUITE" ]; then
        echo "⚠️  No MongoDB apt suite found for $CODENAME — skipping mongosh"
    else
        [ "$MONGO_SUITE" = "$CODENAME" ] \
            || echo "⚠️  MongoDB has no packages for $CODENAME — using the $MONGO_SUITE suite instead"
        echo "deb [ arch=amd64,arm64 signed-by=/etc/apt/keyrings/mongodb-server-8.0.gpg ] \
https://repo.mongodb.org/apt/ubuntu ${MONGO_SUITE}/mongodb-org/8.0 multiverse" \
            | sudo tee /etc/apt/sources.list.d/mongodb-org-8.0.list > /dev/null

        echo "📦 Installing mongosh + mongodb-database-tools..."
        sudo apt-get update
        sudo apt-get install -y mongodb-mongosh mongodb-database-tools
        echo "✅ mongosh installed"
    fi
fi

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
command -v mongosh &>/dev/null && echo "   mongosh   - MongoDB (+ mongodump/mongorestore)"
echo "   pgcli     - PostgreSQL with autocomplete"
echo "   mycli     - MySQL with autocomplete"
echo "   litecli   - SQLite with autocomplete"
