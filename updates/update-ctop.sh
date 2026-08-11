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

CTOP_BIN="$(command -v ctop 2>/dev/null || true)"
if [ -z "$CTOP_BIN" ]; then
    echo "⏭️  Skipping ctop update: ctop is not installed."
    exit 0
fi

CTOP_BIN="$(readlink -f "$CTOP_BIN" 2>/dev/null || true)"
if [ "$CTOP_BIN" != "/usr/local/bin/ctop" ] || [ ! -f "$CTOP_BIN" ] || [ ! -x "$CTOP_BIN" ]; then
    echo "⏭️  Skipping ctop update: ${CTOP_BIN:-the active binary} is not the standalone binary installed by this repository."
    exit 0
fi

if command -v dpkg-query &>/dev/null && dpkg-query -S "$CTOP_BIN" &>/dev/null; then
    echo "⏭️  Skipping ctop update: $CTOP_BIN is owned by a Debian package."
    exit 0
fi

case "$(dpkg --print-architecture)" in
    amd64|arm64) CTOP_ARCH="$(dpkg --print-architecture)" ;;
    *)
        echo "❌ Unsupported ctop architecture: $(dpkg --print-architecture)" >&2
        exit 1
        ;;
esac

for REQUIRED_COMMAND in curl install mktemp mv readlink sha256sum; do
    if ! command -v "$REQUIRED_COMMAND" &>/dev/null; then
        echo "❌ $REQUIRED_COMMAND is required to update ctop" >&2
        exit 1
    fi
done

BEFORE_VERSION=$("$CTOP_BIN" -v 2>/dev/null | head -1 || true)
echo "🚀 Updating ctop..."
echo "   Before: ${BEFORE_VERSION:-version unknown}"

echo "🔍 Resolving latest ctop release..."
CTOP_VERSION=$(latest_github_tag bcicen/ctop)
CTOP_NUM=${CTOP_VERSION#v}
CTOP_ASSET="ctop-${CTOP_NUM}-linux-${CTOP_ARCH}"
CTOP_BASE="https://github.com/bcicen/ctop/releases/download/${CTOP_VERSION}"

CTOP_TMP_DIR=$(mktemp -d)
CTOP_STAGED_BIN=""
cleanup() {
    rm -rf "$CTOP_TMP_DIR"
    if [ -n "$CTOP_STAGED_BIN" ] && [ -e "$CTOP_STAGED_BIN" ]; then
        if [ -w /usr/local/bin ]; then
            rm -f -- "$CTOP_STAGED_BIN"
        else
            sudo rm -f -- "$CTOP_STAGED_BIN"
        fi
    fi
}
trap cleanup EXIT

curl --proto '=https' --tlsv1.2 -fsSL --retry 3 --retry-all-errors \
    -o "$CTOP_TMP_DIR/ctop" "$CTOP_BASE/$CTOP_ASSET"
curl --proto '=https' --tlsv1.2 -fsSL --retry 3 --retry-all-errors \
    -o "$CTOP_TMP_DIR/sha256sums.txt" "$CTOP_BASE/sha256sums.txt"

EXPECTED_SHA=$(awk -v want="$CTOP_ASSET" '$2 == want {print $1; exit}' \
    "$CTOP_TMP_DIR/sha256sums.txt")
[[ "$EXPECTED_SHA" =~ ^[0-9a-fA-F]{64}$ ]] \
    || { echo "❌ ctop checksum manifest is missing a valid digest for $CTOP_ASSET" >&2; exit 1; }
echo "$EXPECTED_SHA  $CTOP_TMP_DIR/ctop" | sha256sum --check --quiet
echo "✅ Checksum verified"

if [ -w /usr/local/bin ]; then
    CTOP_STAGED_BIN=$(mktemp "${CTOP_BIN}.update.XXXXXX")
    install -m 0755 "$CTOP_TMP_DIR/ctop" "$CTOP_STAGED_BIN"
else
    CTOP_STAGED_BIN=$(sudo mktemp "${CTOP_BIN}.update.XXXXXX")
    sudo install -m 0755 "$CTOP_TMP_DIR/ctop" "$CTOP_STAGED_BIN"
fi

STAGED_VERSION=$("$CTOP_STAGED_BIN" -v 2>/dev/null | head -1 || true)
case "$STAGED_VERSION" in
    *"$CTOP_NUM"*) ;;
    *) echo "❌ Staged ctop binary did not report expected version $CTOP_VERSION" >&2; exit 1 ;;
esac

if [ -w /usr/local/bin ]; then
    mv -f -- "$CTOP_STAGED_BIN" "$CTOP_BIN"
else
    sudo mv -f -- "$CTOP_STAGED_BIN" "$CTOP_BIN"
fi
CTOP_STAGED_BIN=""

AFTER_VERSION=$("$CTOP_BIN" -v 2>/dev/null | head -1 || true)
echo "✅ ctop update complete"
echo "   After:  ${AFTER_VERSION:-version unknown}"
