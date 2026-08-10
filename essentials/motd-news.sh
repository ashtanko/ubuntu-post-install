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

echo "🚀 Disabling Ubuntu's motd-news ads..."

# /etc/default/motd-news gates the 50-motd-news update-motd.d script, which
# fetches Canonical's ESM/livepatch nag headlines on every login.
CONFIG_FILE="/etc/default/motd-news"

if [ -f "$CONFIG_FILE" ]; then
    if grep -qE '^ENABLED=0' "$CONFIG_FILE"; then
        echo "✅ motd-news already disabled in $CONFIG_FILE"
    elif grep -qE '^ENABLED=' "$CONFIG_FILE"; then
        echo "🔧 Setting ENABLED=0 in $CONFIG_FILE..."
        sudo sed -i 's/^ENABLED=.*/ENABLED=0/' "$CONFIG_FILE"
        echo "✅ motd-news disabled"
    else
        echo "🔧 Appending ENABLED=0 to $CONFIG_FILE..."
        echo "ENABLED=0" | sudo tee -a "$CONFIG_FILE" >/dev/null
        echo "✅ motd-news disabled"
    fi
else
    echo "⏭️  $CONFIG_FILE not present — nothing to disable there"
fi

# Newer Ubuntu releases fetch the headline via a systemd timer rather than
# (or in addition to) the update-motd.d cron path.
if [ -d /run/systemd/system ] && systemctl list-unit-files motd-news.timer &>/dev/null; then
    if systemctl is-enabled --quiet motd-news.timer 2>/dev/null; then
        echo "🔧 Disabling motd-news.timer..."
        sudo systemctl disable --now motd-news.timer >/dev/null 2>&1 || true
        echo "✅ motd-news.timer disabled"
    else
        echo "✅ motd-news.timer already disabled"
    fi
fi

echo ""
echo "💡 Takes effect on your next login; the current session's banner is unaffected."
