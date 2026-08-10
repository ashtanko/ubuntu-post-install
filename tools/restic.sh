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
GITHUB_HELPER="$REPO_ROOT/lib/github.bash"
# shellcheck source=lib/github.bash
source "$GITHUB_HELPER" || { echo "❌ Missing github helper: $GITHUB_HELPER" >&2; exit 1; }

echo "🚀 Installing restic (deduplicated, encrypted backups)..."

# Complements tools/backup-home.sh (full tarball snapshots) with incremental,
# versioned ones, and speaks rclone remotes natively (tools/rclone.sh).
if command -v restic &>/dev/null; then
    echo "✅ restic already installed ($(restic version 2>/dev/null | head -1))"
    echo "💡 Update with: sudo restic self-update"
    exit 0
fi

ARCH=$(dpkg --print-architecture)
case "$ARCH" in
    amd64|arm64) ;;   # restic's asset names match dpkg's arch names
    *) echo "❌ Unsupported architecture: $ARCH"; exit 1 ;;
esac

if ! command -v bunzip2 &>/dev/null; then
    echo "📦 Installing bzip2 (restic ships a .bz2-compressed binary)..."
    sudo apt-get update
    sudo apt-get install -y bzip2
fi

BIN_DIR="/usr/local/bin"

echo "🔍 Resolving latest restic release..."
RESTIC_VERSION=$(latest_github_tag restic/restic)
RESTIC_NUM=${RESTIC_VERSION#v}
RESTIC_ASSET="restic_${RESTIC_NUM}_linux_${ARCH}.bz2"
RESTIC_BASE="https://github.com/restic/restic/releases/download/${RESTIC_VERSION}"

echo "📦 Downloading restic $RESTIC_VERSION..."
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
wget --tries=3 --waitretry=2 -q --show-progress -O "$TMP/$RESTIC_ASSET" "${RESTIC_BASE}/${RESTIC_ASSET}"

echo "🔒 Verifying checksum..."
RESTIC_CHECKSUMS="$TMP/SHA256SUMS"
curl -fsSL --retry 3 --retry-all-errors -o "$RESTIC_CHECKSUMS" "${RESTIC_BASE}/SHA256SUMS"
EXPECTED_SHA=$(awk -v want="$RESTIC_ASSET" '$2 == want {print $1; exit}' "$RESTIC_CHECKSUMS")
[[ "$EXPECTED_SHA" =~ ^[0-9a-fA-F]{64}$ ]] \
    || { echo "❌ restic checksum manifest is missing a valid digest for $RESTIC_ASSET"; exit 1; }
echo "$EXPECTED_SHA  $TMP/$RESTIC_ASSET" | sha256sum --check --quiet
echo "✅ Checksum verified"

bunzip2 "$TMP/$RESTIC_ASSET"
sudo install -m 0755 "$TMP/${RESTIC_ASSET%.bz2}" "$BIN_DIR/restic"

if ! command -v restic &>/dev/null; then
    echo "❌ restic installation failed or is not in PATH"
    exit 1
fi

echo ""
echo "✅ restic installed ($(restic version 2>/dev/null | head -1)) → $BIN_DIR/restic"
echo "💡 Initialize a local repo:   restic init --repo ~/backups/restic"
echo "💡 Back up your home:         restic -r ~/backups/restic backup ~/Documents"
echo "💡 Straight to an rclone remote (see tools/rclone.sh):"
echo "     restic -r rclone:remote:backups init"
echo "💡 Prune old snapshots:       restic -r <repo> forget --keep-daily 7 --keep-weekly 4 --prune"
