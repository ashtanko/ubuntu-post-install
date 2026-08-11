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

echo "🚀 Running a Lynis security audit..."

if command -v lynis &>/dev/null; then
    echo "✅ Lynis already installed ($(lynis show version 2>/dev/null | head -1))"
else
    echo "📦 Installing lynis..."
    sudo apt-get update
    if ! sudo apt-get install -y lynis; then
        echo "🔍 lynis not found — enabling the universe component and retrying..."
        sudo add-apt-repository -y universe
        sudo apt-get update
        sudo apt-get install -y lynis
    fi
fi

# Like system-info.sh, this is a one-shot report generator, not a persistent
# install step — safe (and expected) to re-run for a fresh snapshot.
OUT="$HOME/lynis-audit-$(date +%Y%m%d-%H%M%S).log"
echo "🔍 Auditing system → $OUT"
echo "   (some checks are skipped without root; that's expected)"

sudo lynis audit system --quick --no-colors 2>&1 | tee "$OUT" | tail -40
sudo chown "$(id -u):$(id -g)" "$OUT" 2>/dev/null || true

echo ""
echo "✅ Audit complete — full report: $OUT"
echo "💡 Lynis also keeps its own logs at /var/log/lynis.log and /var/log/lynis-report.dat"
echo "💡 Re-run any time; hardening index and warnings will change as you act on findings"
