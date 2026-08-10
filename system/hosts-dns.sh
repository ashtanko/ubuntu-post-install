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

echo "🚀 Configuring DNS resolvers..."

# Only touch systemd-resolved. On systems that don't run it (containers, WSL,
# NetworkManager-only DNS, servers using /etc/resolv.conf directly) forcing it
# in would fight the existing resolver setup, so we bow out instead.
if ! command -v resolvectl &>/dev/null && ! command -v systemd-resolve &>/dev/null; then
    echo "⏭️  systemd-resolved not present — skipping (edit /etc/resolv.conf manually if needed)"
    exit 0
fi

if [ ! -d /run/systemd/system ] || ! systemctl list-unit-files systemd-resolved.service &>/dev/null; then
    echo "⏭️  systemd-resolved service not available — skipping"
    exit 0
fi

DNS_SERVERS="${DNS_SERVERS:-1.1.1.1 9.9.9.9}"
DNS_FALLBACK_SERVERS="${DNS_FALLBACK_SERVERS:-1.0.0.1 149.112.112.112}"

DROPIN_DIR="/etc/systemd/resolved.conf.d"
DROPIN_FILE="$DROPIN_DIR/upi-dns.conf"

DESIRED_CONFIG="[Resolve]
DNS=$DNS_SERVERS
FallbackDNS=$DNS_FALLBACK_SERVERS"

sudo mkdir -p "$DROPIN_DIR"

if [ -f "$DROPIN_FILE" ] && printf '%s\n' "$DESIRED_CONFIG" | sudo cmp -s - "$DROPIN_FILE"; then
    echo "✅ DNS config already up to date ($DROPIN_FILE)"
else
    echo "🔧 Writing $DROPIN_FILE (DNS=$DNS_SERVERS, FallbackDNS=$DNS_FALLBACK_SERVERS)..."
    printf '%s\n' "$DESIRED_CONFIG" | sudo tee "$DROPIN_FILE" >/dev/null

    if ! systemctl is-enabled --quiet systemd-resolved 2>/dev/null; then
        sudo systemctl enable systemd-resolved >/dev/null 2>&1 || true
    fi

    echo "🔄 Restarting systemd-resolved..."
    sudo systemctl restart systemd-resolved
    echo "✅ DNS resolvers configured"
fi

echo ""
resolvectl status 2>/dev/null | grep -A2 "Current DNS Server\|DNS Servers" | sed 's/^/   /' || true
