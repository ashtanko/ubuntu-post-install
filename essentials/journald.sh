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

echo "🚀 Capping systemd-journald disk usage..."

# journald.conf.d only means anything when systemd-journald is the logging
# daemon in use.
if [ ! -d /run/systemd/system ] || ! command -v journalctl &>/dev/null; then
    echo "⏭️  systemd-journald not present — skipping"
    exit 0
fi

JOURNAL_MAX_USE="${JOURNAL_MAX_USE:-200M}"

# systemd disk-size syntax: an integer, optionally suffixed with K/M/G/T, or a
# bare percentage like "10%".
if ! [[ "$JOURNAL_MAX_USE" =~ ^[0-9]+(%|[KMGT]?)$ ]]; then
    echo "❌ JOURNAL_MAX_USE must look like 200M, 1G, or 10% — got '$JOURNAL_MAX_USE'"
    exit 1
fi

DROPIN_DIR="/etc/systemd/journald.conf.d"
DROPIN_FILE="$DROPIN_DIR/99-upi-journal.conf"

DESIRED_CONFIG="[Journal]
SystemMaxUse=$JOURNAL_MAX_USE"

sudo mkdir -p "$DROPIN_DIR"

if [ -f "$DROPIN_FILE" ] && printf '%s\n' "$DESIRED_CONFIG" | sudo cmp -s - "$DROPIN_FILE"; then
    echo "✅ Journal cap already set to $JOURNAL_MAX_USE"
else
    echo "🔧 Writing $DROPIN_FILE (SystemMaxUse=$JOURNAL_MAX_USE)..."
    printf '%s\n' "$DESIRED_CONFIG" | sudo tee "$DROPIN_FILE" >/dev/null

    echo "🔄 Restarting systemd-journald..."
    sudo systemctl restart systemd-journald
    echo "✅ Journal disk usage capped at $JOURNAL_MAX_USE"
fi

echo ""
journalctl --disk-usage 2>/dev/null | sed 's/^/   /' || true
