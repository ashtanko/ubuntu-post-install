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

# Manual utility: pack the user's critical secrets/configs into a single
# tarball, optionally GPG-encrypted. Run this BEFORE distro upgrades, hardware
# swaps, or as a periodic safety net.

DEST_DIR="${BACKUP_DIR:-$HOME/backups}"
ENCRYPT="${BACKUP_ENCRYPT:-no}"          # yes | no
RECIPIENT="${BACKUP_GPG_RECIPIENT:-${GIT_EMAIL:-}}"

mkdir -p "$DEST_DIR"
TS=$(date +%Y%m%d-%H%M%S)
ARCHIVE="$DEST_DIR/home-backup-$TS.tar.gz"
PLAIN_TMP=""
ENCRYPTED_TMP=""

cleanup() {
    if [ -n "$PLAIN_TMP" ] && [ -f "$PLAIN_TMP" ]; then
        shred -u "$PLAIN_TMP" 2>/dev/null || rm -f "$PLAIN_TMP"
    fi
    [ -z "$ENCRYPTED_TMP" ] || rm -f "$ENCRYPTED_TMP"
}
trap cleanup EXIT

if [[ "$ENCRYPT" == "yes" ]]; then
    if [ -z "$RECIPIENT" ]; then
        echo "❌ BACKUP_ENCRYPT=yes but no recipient (BACKUP_GPG_RECIPIENT or GIT_EMAIL)"
        exit 1
    fi
    if ! command -v gpg &>/dev/null; then
        echo "❌ gpg not installed"
        exit 1
    fi
fi

# Critical paths — only include what actually exists, skip what's missing
CANDIDATES=(
    "$HOME/.ssh"
    "$HOME/.gnupg"
    "$HOME/.aws"
    "$HOME/.kube"
    "$HOME/.config"
    "$HOME/.bashrc"
    "$HOME/.zshrc"
    "$HOME/.gitconfig"
    "$HOME/.profile"
)

INCLUDE=()
for p in "${CANDIDATES[@]}"; do
    if [ -e "$p" ]; then
        INCLUDE+=("${p#"$HOME"/}")  # store as relative paths
    fi
done

if [ ${#INCLUDE[@]} -eq 0 ]; then
    echo "⚠️  Nothing to back up — none of the candidate paths exist"
    exit 0
fi

echo "🚀 Backing up:"
printf '   • %s\n' "${INCLUDE[@]}"
echo ""

# Use --ignore-failed-read so a single unreadable file (e.g. a stale socket)
# doesn't abort the whole archive
PLAIN_TMP=$(mktemp "$DEST_DIR/.home-backup-${TS}.XXXXXX.tar.gz")
tar --ignore-failed-read \
    --exclude='*/Cache' --exclude='*/cache' --exclude='*/Code Cache' \
    --exclude='*/CachedData' --exclude='*/GPUCache' \
    -C "$HOME" -czf "$PLAIN_TMP" "${INCLUDE[@]}"

chmod 600 "$PLAIN_TMP"

if [[ "$ENCRYPT" == "yes" ]]; then
    echo "🔒 Encrypting to $RECIPIENT..."
    ENCRYPTED_TMP=$(mktemp "$DEST_DIR/.home-backup-${TS}.XXXXXX.tar.gz.gpg")
    gpg --yes --batch --encrypt --recipient "$RECIPIENT" --output "$ENCRYPTED_TMP" "$PLAIN_TMP"
    chmod 600 "$ENCRYPTED_TMP"
    mv "$ENCRYPTED_TMP" "$ARCHIVE.gpg"
    ENCRYPTED_TMP=""
    shred -u "$PLAIN_TMP" 2>/dev/null || rm -f "$PLAIN_TMP"
    PLAIN_TMP=""
    ARCHIVE="$ARCHIVE.gpg"
else
    mv "$PLAIN_TMP" "$ARCHIVE"
    PLAIN_TMP=""
fi

SIZE=$(du -h "$ARCHIVE" | awk '{print $1}')
echo ""
echo "✅ Backup created: $ARCHIVE ($SIZE)"
echo "💡 Restore with: tar -xzf $ARCHIVE -C \$HOME"
[[ "$ENCRYPT" == "yes" ]] && echo "💡 Decrypt first:  gpg --decrypt $ARCHIVE > out.tar.gz"
