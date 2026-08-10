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

echo "🚀 Raising inotify watch and open-file limits..."

# Ubuntu's stock limits are tuned for a generic server, not a box running an
# IDE, docker, and a bundler all watching large repos at once — that's what
# throws ENOSPC from `inotify_add_watch` or "too many open files".
INOTIFY_MAX_WATCHES="${INOTIFY_MAX_WATCHES:-524288}"
INOTIFY_MAX_INSTANCES="${INOTIFY_MAX_INSTANCES:-1024}"
NOFILE_LIMIT="${NOFILE_LIMIT:-1048576}"

for name in INOTIFY_MAX_WATCHES INOTIFY_MAX_INSTANCES NOFILE_LIMIT; do
    if ! [[ "${!name}" =~ ^[0-9]+$ ]]; then
        echo "❌ $name must be a positive integer — got '${!name}'"
        exit 1
    fi
done

# ── inotify watches (sysctl, applies immediately) ───────────────────────────
SYSCTL_FILE="/etc/sysctl.d/99-upi-inotify.conf"
DESIRED_SYSCTL="fs.inotify.max_user_watches=$INOTIFY_MAX_WATCHES
fs.inotify.max_user_instances=$INOTIFY_MAX_INSTANCES"

if [ -f "$SYSCTL_FILE" ] && printf '%s\n' "$DESIRED_SYSCTL" | sudo cmp -s - "$SYSCTL_FILE"; then
    echo "✅ inotify limits already set (watches=$INOTIFY_MAX_WATCHES, instances=$INOTIFY_MAX_INSTANCES)"
else
    echo "🔧 Writing $SYSCTL_FILE..."
    printf '%s\n' "$DESIRED_SYSCTL" | sudo tee "$SYSCTL_FILE" >/dev/null
    sudo sysctl -p "$SYSCTL_FILE" >/dev/null
    echo "✅ inotify limits applied (watches=$INOTIFY_MAX_WATCHES, instances=$INOTIFY_MAX_INSTANCES)"
fi

# ── open-file limits (pam_limits, needs a new login session) ───────────────
LIMITS_FILE="/etc/security/limits.d/99-upi-nofile.conf"
DESIRED_LIMITS="* soft nofile $NOFILE_LIMIT
* hard nofile $NOFILE_LIMIT"

if [ -f "$LIMITS_FILE" ] && printf '%s\n' "$DESIRED_LIMITS" | sudo cmp -s - "$LIMITS_FILE"; then
    echo "✅ Open-file limit already set to $NOFILE_LIMIT"
else
    echo "🔧 Writing $LIMITS_FILE..."
    printf '%s\n' "$DESIRED_LIMITS" | sudo tee "$LIMITS_FILE" >/dev/null
    echo "✅ Open-file limit set to $NOFILE_LIMIT"
fi

echo ""
echo "✅ Current values:"
echo "   fs.inotify.max_user_watches   = $(cat /proc/sys/fs/inotify/max_user_watches 2>/dev/null || echo '?')"
echo "   fs.inotify.max_user_instances = $(cat /proc/sys/fs/inotify/max_user_instances 2>/dev/null || echo '?')"
echo "💡 The nofile limit needs a new login session (log out/in, or new SSH session) to take effect."
