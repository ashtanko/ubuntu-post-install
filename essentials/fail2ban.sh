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

echo "🚀 Configuring fail2ban (SSH brute-force protection)..."

if [[ "${ENABLE_FAIL2BAN:-yes}" == "no" ]]; then
    echo "⏭️  Skipping fail2ban (ENABLE_FAIL2BAN=no)"
    exit 0
fi

if command -v fail2ban-client &>/dev/null; then
    echo "✅ fail2ban already installed ($(fail2ban-client --version 2>/dev/null | head -1))"
else
    echo "📦 Installing fail2ban..."
    sudo apt-get update
    sudo apt-get install -y fail2ban
fi

# .local files are read after jail.conf and jail.d/*.conf, so this overrides
# the shipped defaults without editing (and losing on package upgrade) the
# distro-owned jail.conf.
DROPIN_DIR="/etc/fail2ban/jail.d"
DROPIN_FILE="$DROPIN_DIR/99-upi-sshd.local"

BANTIME="${FAIL2BAN_BANTIME:-1h}"
FINDTIME="${FAIL2BAN_FINDTIME:-10m}"
MAXRETRY="${FAIL2BAN_MAXRETRY:-5}"

DESIRED_CONFIG="[sshd]
enabled  = true
port     = ssh
maxretry = $MAXRETRY
findtime = $FINDTIME
bantime  = $BANTIME"

sudo mkdir -p "$DROPIN_DIR"

if [ -f "$DROPIN_FILE" ] && printf '%s\n' "$DESIRED_CONFIG" | sudo cmp -s - "$DROPIN_FILE"; then
    echo "✅ sshd jail already configured (maxretry=$MAXRETRY, findtime=$FINDTIME, bantime=$BANTIME)"
else
    echo "🔧 Writing $DROPIN_FILE..."
    printf '%s\n' "$DESIRED_CONFIG" | sudo tee "$DROPIN_FILE" >/dev/null
    echo "✅ sshd jail configured (maxretry=$MAXRETRY, findtime=$FINDTIME, bantime=$BANTIME)"
fi

# jail.d/*.local only takes effect once fail2ban is (re)started; needs
# systemd as PID 1 to manage the service.
if [ -d /run/systemd/system ] && command -v systemctl &>/dev/null; then
    if systemctl is-active --quiet fail2ban 2>/dev/null; then
        echo "🔄 Restarting fail2ban to pick up the sshd jail..."
        sudo systemctl restart fail2ban
    else
        echo "🔧 Enabling + starting fail2ban..."
        sudo systemctl enable --now fail2ban
    fi
    echo ""
    sudo fail2ban-client status sshd 2>/dev/null | sed 's/^/   /' || true
else
    echo "⚠️  No systemd — fail2ban is configured but not started; start it manually where systemd is available"
fi

echo ""
echo "✅ fail2ban ready."
echo "💡 Check ban status any time with: sudo fail2ban-client status sshd"
echo "💡 Unban an IP with:              sudo fail2ban-client set sshd unbanip <ip>"
