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

echo "🚀 Installing Antigravity..."

ARCH=$(dpkg --print-architecture)
case "$ARCH" in
    amd64|arm64) ;;
    *)
        echo "❌ Antigravity publishes amd64 and arm64 packages only (this system: $ARCH)" >&2
        exit 1
        ;;
esac

KEYRING_PATH="/etc/apt/keyrings/antigravity-repo-key.gpg"
SOURCE_LIST="/etc/apt/sources.list.d/antigravity.list"

ALREADY_INSTALLED=no
if dpkg-query -W -f='${Status}' antigravity 2>/dev/null | grep -q 'ok installed'; then
    ALREADY_INSTALLED=yes
fi

# The package alone is not the whole desired state: without the repository
# wired up, apt has no upgrade candidate and the installation silently stops
# receiving updates. Re-run the repo setup whenever either piece is missing.
if [ "$ALREADY_INSTALLED" = yes ] && [ -f "$KEYRING_PATH" ] && [ -f "$SOURCE_LIST" ]; then
    echo "✅ Antigravity already installed ($(dpkg-query -W -f='${Version}' antigravity))"
    echo "💡 Update it later with: bash updates/update-antigravity.sh"
    exit 0
fi

echo "📦 Installing repository prerequisites..."
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT
KEY_FILE="$TMP_DIR/antigravity-repo-key.asc"
KEYRING_FILE="$TMP_DIR/antigravity-repo-key.gpg"
GPG_HOME="$TMP_DIR/gnupg"
# Artifact Registry Repository Signer <artifact-registry-repository-signer@google.com>
EXPECTED_FINGERPRINT="35BAA0B33E9EB396F59CA838C0BA5CE6DC6315A3"

echo "📥 Downloading and verifying the Google Artifact Registry signing key..."
curl -fsSL --retry 3 --retry-all-errors \
    -o "$KEY_FILE" https://us-central1-apt.pkg.dev/doc/repo-signing-key.gpg
mkdir -m 700 "$GPG_HOME"
FINGERPRINT=$(GNUPGHOME="$GPG_HOME" gpg --batch --no-options --show-keys --with-colons \
    "$KEY_FILE" 2>/dev/null | awk -F: '$1 == "fpr" { print $10; exit }')
if [ "$FINGERPRINT" != "$EXPECTED_FINGERPRINT" ]; then
    echo "❌ Antigravity repository signing key fingerprint mismatch" >&2
    echo "   expected: $EXPECTED_FINGERPRINT" >&2
    echo "   received: ${FINGERPRINT:-missing}" >&2
    exit 1
fi

echo "🔧 Configuring the Antigravity APT repository..."
GNUPGHOME="$GPG_HOME" gpg --batch --yes --dearmor -o "$KEYRING_FILE" "$KEY_FILE"
sudo install -D -o root -g root -m 644 "$KEYRING_FILE" "$KEYRING_PATH"
echo "deb [arch=$ARCH signed-by=$KEYRING_PATH] https://us-central1-apt.pkg.dev/projects/antigravity-auto-updater-dev antigravity-debian main" \
    | sudo tee "$SOURCE_LIST" >/dev/null

sudo apt-get update

if [ "$ALREADY_INSTALLED" = yes ]; then
    echo "✅ Antigravity already installed ($(dpkg-query -W -f='${Version}' antigravity))"
    echo "🔧 Its APT repository was missing and has been restored, so upgrades resume"
    echo "💡 Update it now with: bash updates/update-antigravity.sh"
    exit 0
fi

echo "📦 Installing Antigravity..."
sudo apt-get install -y antigravity

if ! dpkg-query -W -f='${Status}' antigravity 2>/dev/null | grep -q 'ok installed'; then
    echo "❌ Antigravity installation failed" >&2
    exit 1
fi

echo "✅ Antigravity installed successfully ($(dpkg-query -W -f='${Version}' antigravity))"
echo "💡 Launch it from the app grid or run 'antigravity'; sign in with a Google account on first start"
echo "💡 Later upgrades: bash updates/update-antigravity.sh (or the normal 'apt upgrade' cycle)"
