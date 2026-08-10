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

echo "🚀 Installing rclone (cloud storage sync)..."

if command -v rclone &>/dev/null; then
    echo "✅ rclone already installed ($(rclone version 2>/dev/null | head -1))"
else
    echo "📦 Ensuring curl + unzip are present..."
    sudo apt-get update
    sudo apt-get install -y curl unzip

    echo "📦 Installing rclone via official installer..."
    RCLONE_INSTALLER=$(mktemp)
    trap 'rm -f "$RCLONE_INSTALLER"' EXIT
    curl -fsSL --retry 3 --retry-all-errors -o "$RCLONE_INSTALLER" https://rclone.org/install.sh
    sudo bash "$RCLONE_INSTALLER"
    rm -f "$RCLONE_INSTALLER"
    trap - EXIT

    if ! command -v rclone &>/dev/null; then
        echo "❌ rclone installation failed or is not in PATH"
        exit 1
    fi
    echo "✅ rclone installed ($(rclone version 2>/dev/null | head -1))"
fi

echo ""
echo "✅ rclone ready!"
echo "💡 Complements tools/backup-home.sh: add a remote, then sync the backup dir offsite."
echo "💡 Configure a remote (interactive):  rclone config"
echo "💡 Example offsite copy:              rclone copy \"\$BACKUP_DIR\" remote:backups"
