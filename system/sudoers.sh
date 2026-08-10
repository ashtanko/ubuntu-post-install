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

echo "🚀 Configuring sudo timestamp timeout..."

# This script intentionally does ONE thing — extend how long a sudo prompt
# stays "unlocked" — and only when explicitly opted into. It never sets up
# passwordless sudo; that's a much bigger security trade-off than a bash
# provisioning script should make on your behalf.
if [ -z "${SUDO_TIMESTAMP_TIMEOUT_MINUTES:-}" ]; then
    echo "⏭️  SUDO_TIMESTAMP_TIMEOUT_MINUTES not set — skipping (opt-in only)"
    exit 0
fi

TIMEOUT="$SUDO_TIMESTAMP_TIMEOUT_MINUTES"
# sudo accepts negative (never expire) and non-negative integers.
if ! [[ "$TIMEOUT" =~ ^-?[0-9]+$ ]]; then
    echo "❌ SUDO_TIMESTAMP_TIMEOUT_MINUTES must be an integer (minutes; -1 = never expire): got '$TIMEOUT'"
    exit 1
fi

DROPIN_FILE="/etc/sudoers.d/99-upi-timeout"
DESIRED_CONFIG="Defaults timestamp_timeout=$TIMEOUT"

if [ -f "$DROPIN_FILE" ] && printf '%s\n' "$DESIRED_CONFIG" | sudo cmp -s - "$DROPIN_FILE"; then
    echo "✅ sudo timestamp_timeout already set to $TIMEOUT"
    exit 0
fi

TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT
printf '%s\n' "$DESIRED_CONFIG" > "$TMP"

# Validate before it ever touches /etc/sudoers.d — a bad drop-in there can lock
# sudo entirely.
if ! sudo visudo -cf "$TMP"; then
    echo "❌ Generated sudoers snippet failed validation — aborting without installing it"
    exit 1
fi

echo "🔧 Installing $DROPIN_FILE (timestamp_timeout=$TIMEOUT)..."
sudo install -m 0440 -o root -g root "$TMP" "$DROPIN_FILE"
echo "✅ sudo timestamp_timeout set to $TIMEOUT minute(s)"
