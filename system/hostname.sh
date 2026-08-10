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

echo "🚀 Setting system hostname..."

CURRENT_HOSTNAME="$(hostname)"

# Resolve desired hostname: env var → interactive prompt (default: current)
DESIRED_HOSTNAME="${NEW_HOSTNAME:-}"
if [ -z "$DESIRED_HOSTNAME" ]; then
    if [ -t 0 ]; then
        echo -n "🖥️  Enter hostname [$CURRENT_HOSTNAME]: "
        read -r DESIRED_HOSTNAME
        DESIRED_HOSTNAME="${DESIRED_HOSTNAME:-$CURRENT_HOSTNAME}"
    else
        echo "⏭️  NEW_HOSTNAME not set and no TTY to prompt — skipping"
        exit 0
    fi
fi

# RFC 1123 label: letters, digits, hyphens; 1-63 chars; no leading/trailing hyphen
if ! [[ "$DESIRED_HOSTNAME" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$ ]]; then
    echo "❌ Invalid hostname: $DESIRED_HOSTNAME"
    exit 1
fi

if [ "$DESIRED_HOSTNAME" = "$CURRENT_HOSTNAME" ]; then
    echo "✅ Hostname already $CURRENT_HOSTNAME"
else
    echo "🔧 Setting hostname to $DESIRED_HOSTNAME..."
    if command -v hostnamectl &>/dev/null; then
        sudo hostnamectl set-hostname "$DESIRED_HOSTNAME"
    else
        echo "$DESIRED_HOSTNAME" | sudo tee /etc/hostname >/dev/null
        sudo hostname "$DESIRED_HOSTNAME"
    fi
    echo "✅ Hostname set to $DESIRED_HOSTNAME"
fi

# Keep the 127.0.1.1 loopback entry (used to resolve the local hostname) in sync
if grep -qE '^127\.0\.1\.1[[:space:]]' /etc/hosts; then
    if grep -qE "^127\.0\.1\.1[[:space:]]+$DESIRED_HOSTNAME([[:space:]]|\$)" /etc/hosts; then
        echo "✅ /etc/hosts already maps 127.0.1.1 → $DESIRED_HOSTNAME"
    else
        echo "🔧 Updating 127.0.1.1 entry in /etc/hosts..."
        sudo sed -i "s/^127\.0\.1\.1[[:space:]].*/127.0.1.1\t$DESIRED_HOSTNAME/" /etc/hosts
        echo "✅ /etc/hosts updated"
    fi
else
    echo "🔧 Adding 127.0.1.1 entry to /etc/hosts..."
    printf '127.0.1.1\t%s\n' "$DESIRED_HOSTNAME" | sudo tee -a /etc/hosts >/dev/null
    echo "✅ /etc/hosts updated"
fi

echo "💡 Some apps only pick up the new hostname after a re-login or reboot."
