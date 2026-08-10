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

echo "🚀 Installing network diagnostic tools..."

# Rounds out the diagnostics story tools/wireshark.sh starts (packet capture)
# and system/hosts-dns.sh implies (resolver configuration worth verifying).
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

# Reachability + routing
install_if_missing mtr       mtr-tiny
install_if_missing traceroute traceroute
install_if_missing nmap      nmap

# DNS — dig/nslookup, for verifying what system/hosts-dns.sh configured
install_if_missing dig       bind9-dnsutils

# Sockets / listening ports
install_if_missing ss        iproute2
install_if_missing lsof      lsof
install_if_missing nc        netcat-openbsd

# Throughput testing
install_if_missing iperf3    iperf3

# HTTP clients
install_if_missing httpie    httpie
install_if_missing whois     whois

echo ""
echo "✅ Network tools installed!"
echo "   mtr        - continuous traceroute + loss stats"
echo "   nmap       - port/host scanner"
echo "   dig        - DNS lookups (verify system/hosts-dns.sh with: dig +short example.com)"
echo "   ss         - socket/listening-port inspection (ss -tulpn)"
echo "   lsof       - which process holds which file/port"
echo "   nc         - raw TCP/UDP connections"
echo "   iperf3     - bandwidth benchmarking between two hosts"
echo "   http       - HTTPie, human-friendly HTTP client"
echo "   whois      - domain/IP registration lookups"
echo "💡 Only scan hosts and networks you own or are authorised to test."
