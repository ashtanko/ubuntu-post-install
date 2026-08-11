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

GITLEAKS_BIN="$(command -v gitleaks 2>/dev/null || true)"
if [ -z "$GITLEAKS_BIN" ]; then
    echo "⏭️  Skipping gitleaks update: gitleaks is not installed."
    exit 0
fi

GITLEAKS_BIN="$(readlink -f "$GITLEAKS_BIN" 2>/dev/null || true)"
if [ "$GITLEAKS_BIN" != "/usr/local/bin/gitleaks" ] \
    || [ ! -f "$GITLEAKS_BIN" ] || [ ! -x "$GITLEAKS_BIN" ]; then
    echo "⏭️  Skipping gitleaks update: ${GITLEAKS_BIN:-the active binary} is not the standalone binary installed by this repository."
    exit 0
fi

if command -v dpkg-query &>/dev/null && dpkg-query -S "$GITLEAKS_BIN" &>/dev/null; then
    echo "⏭️  Skipping gitleaks update: $GITLEAKS_BIN is owned by a Debian package."
    exit 0
fi

case "$(dpkg --print-architecture)" in
    amd64) GITLEAKS_ARCH="x64" ;;
    arm64) GITLEAKS_ARCH="arm64" ;;
    *)
        echo "❌ Unsupported gitleaks architecture: $(dpkg --print-architecture)" >&2
        exit 1
        ;;
esac

for REQUIRED_COMMAND in curl install mktemp mv readlink sha256sum tar; do
    if ! command -v "$REQUIRED_COMMAND" &>/dev/null; then
        echo "❌ $REQUIRED_COMMAND is required to update gitleaks" >&2
        exit 1
    fi
done

BEFORE_VERSION=$("$GITLEAKS_BIN" version 2>/dev/null | head -1 || true)
echo "🚀 Updating gitleaks..."
echo "   Before: ${BEFORE_VERSION:-version unknown}"

echo "🔍 Resolving latest gitleaks release..."
GITLEAKS_VERSION=$(latest_github_tag gitleaks/gitleaks)
GITLEAKS_NUM=${GITLEAKS_VERSION#v}
GITLEAKS_ASSET="gitleaks_${GITLEAKS_NUM}_linux_${GITLEAKS_ARCH}.tar.gz"
GITLEAKS_BASE="https://github.com/gitleaks/gitleaks/releases/download/${GITLEAKS_VERSION}"

GITLEAKS_TMP_DIR=$(mktemp -d)
GITLEAKS_STAGED_BIN=""
cleanup() {
    rm -rf "$GITLEAKS_TMP_DIR"
    if [ -n "$GITLEAKS_STAGED_BIN" ] && [ -e "$GITLEAKS_STAGED_BIN" ]; then
        if [ -w /usr/local/bin ]; then
            rm -f -- "$GITLEAKS_STAGED_BIN"
        else
            sudo rm -f -- "$GITLEAKS_STAGED_BIN"
        fi
    fi
}
trap cleanup EXIT

curl --proto '=https' --tlsv1.2 -fsSL --retry 3 --retry-all-errors \
    -o "$GITLEAKS_TMP_DIR/$GITLEAKS_ASSET" "$GITLEAKS_BASE/$GITLEAKS_ASSET"
curl --proto '=https' --tlsv1.2 -fsSL --retry 3 --retry-all-errors \
    -o "$GITLEAKS_TMP_DIR/checksums.txt" \
    "$GITLEAKS_BASE/gitleaks_${GITLEAKS_NUM}_checksums.txt"

EXPECTED_SHA=$(awk -v want="$GITLEAKS_ASSET" '$2 == want {print $1; exit}' \
    "$GITLEAKS_TMP_DIR/checksums.txt")
[[ "$EXPECTED_SHA" =~ ^[0-9a-fA-F]{64}$ ]] \
    || { echo "❌ gitleaks checksum manifest is missing a valid digest for $GITLEAKS_ASSET" >&2; exit 1; }
echo "$EXPECTED_SHA  $GITLEAKS_TMP_DIR/$GITLEAKS_ASSET" | sha256sum --check --quiet
echo "✅ Checksum verified"

tar -xzf "$GITLEAKS_TMP_DIR/$GITLEAKS_ASSET" -C "$GITLEAKS_TMP_DIR" gitleaks
[ -f "$GITLEAKS_TMP_DIR/gitleaks" ] \
    || { echo "❌ gitleaks binary not found in the downloaded archive" >&2; exit 1; }

if [ -w /usr/local/bin ]; then
    GITLEAKS_STAGED_BIN=$(mktemp "${GITLEAKS_BIN}.update.XXXXXX")
    install -m 0755 "$GITLEAKS_TMP_DIR/gitleaks" "$GITLEAKS_STAGED_BIN"
else
    GITLEAKS_STAGED_BIN=$(sudo mktemp "${GITLEAKS_BIN}.update.XXXXXX")
    sudo install -m 0755 "$GITLEAKS_TMP_DIR/gitleaks" "$GITLEAKS_STAGED_BIN"
fi

STAGED_VERSION=$("$GITLEAKS_STAGED_BIN" version 2>/dev/null | head -1 || true)
case "$STAGED_VERSION" in
    *"$GITLEAKS_NUM"*) ;;
    *) echo "❌ Staged gitleaks binary did not report expected version $GITLEAKS_VERSION" >&2; exit 1 ;;
esac

if [ -w /usr/local/bin ]; then
    mv -f -- "$GITLEAKS_STAGED_BIN" "$GITLEAKS_BIN"
else
    sudo mv -f -- "$GITLEAKS_STAGED_BIN" "$GITLEAKS_BIN"
fi
GITLEAKS_STAGED_BIN=""

AFTER_VERSION=$("$GITLEAKS_BIN" version 2>/dev/null | head -1 || true)
echo "✅ gitleaks update complete"
echo "   After:  ${AFTER_VERSION:-version unknown}"
