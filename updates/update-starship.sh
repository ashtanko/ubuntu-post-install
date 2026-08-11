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

STARSHIP_BIN="$HOME/.local/bin/starship"
if [ ! -x "$STARSHIP_BIN" ]; then
    echo "⏭️  The user-local Starship installation was not found; skipping update."
    exit 0
fi
if [ -L "$STARSHIP_BIN" ] || [ ! -f "$STARSHIP_BIN" ] || [ ! -O "$STARSHIP_BIN" ]; then
    echo "⏭️  Skipping Starship update: $STARSHIP_BIN is not a user-owned standalone binary."
    exit 0
fi

case "$(uname -m)" in
    x86_64) STARSHIP_ARCH="x86_64" ;;
    aarch64) STARSHIP_ARCH="aarch64" ;;
    *)
        echo "❌ Unsupported Starship architecture: $(uname -m)" >&2
        exit 1
        ;;
esac

for REQUIRED_COMMAND in curl install mktemp mv sha256sum tar; do
    if ! command -v "$REQUIRED_COMMAND" &>/dev/null; then
        echo "❌ $REQUIRED_COMMAND is required to update Starship" >&2
        exit 1
    fi
done

BEFORE_VERSION=$("$STARSHIP_BIN" --version 2>/dev/null | head -1 || true)
echo "🚀 Updating Starship..."
echo "   Before: ${BEFORE_VERSION:-version unknown}"

echo "🔍 Resolving latest Starship release..."
STARSHIP_VERSION=$(latest_github_tag starship/starship)
STARSHIP_ASSET="starship-${STARSHIP_ARCH}-unknown-linux-musl.tar.gz"
STARSHIP_BASE="https://github.com/starship/starship/releases/download/${STARSHIP_VERSION}"

STARSHIP_TMP_DIR=$(mktemp -d)
STARSHIP_STAGED_BIN=""
cleanup() {
    rm -rf "$STARSHIP_TMP_DIR"
    if [ -n "$STARSHIP_STAGED_BIN" ]; then
        rm -f -- "$STARSHIP_STAGED_BIN"
    fi
}
trap cleanup EXIT
STARSHIP_STAGED_BIN=$(mktemp "${STARSHIP_BIN}.update.XXXXXX")

curl --proto '=https' --tlsv1.2 -fsSL --retry 3 --retry-all-errors \
    -o "$STARSHIP_TMP_DIR/$STARSHIP_ASSET" "$STARSHIP_BASE/$STARSHIP_ASSET"
curl --proto '=https' --tlsv1.2 -fsSL --retry 3 --retry-all-errors \
    -o "$STARSHIP_TMP_DIR/$STARSHIP_ASSET.sha256" \
    "$STARSHIP_BASE/$STARSHIP_ASSET.sha256"

EXPECTED_SHA=$(awk 'NR == 1 {print $1}' "$STARSHIP_TMP_DIR/$STARSHIP_ASSET.sha256")
[[ "$EXPECTED_SHA" =~ ^[0-9a-fA-F]{64}$ ]] \
    || { echo "❌ Starship checksum file does not contain a valid SHA-256 digest" >&2; exit 1; }
echo "$EXPECTED_SHA  $STARSHIP_TMP_DIR/$STARSHIP_ASSET" | sha256sum --check --quiet
echo "✅ Checksum verified"

tar -xzf "$STARSHIP_TMP_DIR/$STARSHIP_ASSET" -C "$STARSHIP_TMP_DIR" starship
[ -f "$STARSHIP_TMP_DIR/starship" ] \
    || { echo "❌ starship was not found in the downloaded archive" >&2; exit 1; }
install -m 0755 "$STARSHIP_TMP_DIR/starship" "$STARSHIP_STAGED_BIN"
"$STARSHIP_STAGED_BIN" --version >/dev/null 2>&1 \
    || { echo "❌ Staged Starship binary failed validation" >&2; exit 1; }
mv -f -- "$STARSHIP_STAGED_BIN" "$STARSHIP_BIN"

AFTER_VERSION=$("$STARSHIP_BIN" --version 2>/dev/null | head -1 || true)
echo "✅ Starship update complete"
echo "   After:  ${AFTER_VERSION:-version unknown}"
