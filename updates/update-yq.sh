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

YQ_BIN="$(command -v yq 2>/dev/null || true)"
if [ -z "$YQ_BIN" ]; then
    echo "⏭️  Skipping yq update: yq is not installed."
    exit 0
fi

YQ_BIN="$(readlink -f "$YQ_BIN" 2>/dev/null || true)"
if [ "$YQ_BIN" != "/usr/local/bin/yq" ]; then
    echo "⏭️  Skipping yq update: ${YQ_BIN:-the active binary} is not the standalone binary installed by this repository."
    exit 0
fi

if command -v dpkg-query &>/dev/null && dpkg-query -S "$YQ_BIN" &>/dev/null; then
    echo "⏭️  Skipping yq update: $YQ_BIN is owned by a Debian package."
    exit 0
fi

case "$(dpkg --print-architecture)" in
    amd64) YQ_ARCH="amd64" ;;
    arm64) YQ_ARCH="arm64" ;;
    *)
        echo "❌ Unsupported yq architecture: $(dpkg --print-architecture)" >&2
        exit 1
        ;;
esac

for REQUIRED_COMMAND in curl sha256sum tar; do
    if ! command -v "$REQUIRED_COMMAND" &>/dev/null; then
        echo "❌ $REQUIRED_COMMAND is required to update yq" >&2
        exit 1
    fi
done

BEFORE_VERSION=$("$YQ_BIN" --version 2>/dev/null | head -1 || true)
echo "🚀 Updating yq..."
echo "   Before: ${BEFORE_VERSION:-version unknown}"

echo "🔍 Resolving latest yq release..."
YQ_VERSION=$(latest_github_tag mikefarah/yq)
YQ_BINARY="yq_linux_${YQ_ARCH}"
YQ_ASSET="${YQ_BINARY}.tar.gz"
YQ_BASE="https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}"

YQ_TMP_DIR=$(mktemp -d)
YQ_STAGED_BIN=""
cleanup() {
    rm -rf "$YQ_TMP_DIR"
    if [ -n "$YQ_STAGED_BIN" ] && [ -e "$YQ_STAGED_BIN" ]; then
        if [ -w /usr/local/bin ]; then
            rm -f -- "$YQ_STAGED_BIN"
        else
            sudo rm -f -- "$YQ_STAGED_BIN"
        fi
    fi
}
trap cleanup EXIT

curl --proto '=https' --tlsv1.2 -fsSL --retry 3 --retry-all-errors \
    -o "$YQ_TMP_DIR/$YQ_ASSET" "$YQ_BASE/$YQ_ASSET"
curl --proto '=https' --tlsv1.2 -fsSL --retry 3 --retry-all-errors \
    -o "$YQ_TMP_DIR/checksums_hashes_order" "$YQ_BASE/checksums_hashes_order"
curl --proto '=https' --tlsv1.2 -fsSL --retry 3 --retry-all-errors \
    -o "$YQ_TMP_DIR/checksums" "$YQ_BASE/checksums"

SHA_LINE=$(grep -n '^SHA-256$' "$YQ_TMP_DIR/checksums_hashes_order" | cut -d: -f1)
[[ "$SHA_LINE" =~ ^[0-9]+$ ]] \
    || { echo "❌ Could not locate SHA-256 in yq's checksum algorithm order" >&2; exit 1; }
EXPECTED_SHA=$(awk -v want="$YQ_ASSET" -v col="$((SHA_LINE + 1))" \
    '$1 == want {print $col; exit}' "$YQ_TMP_DIR/checksums")
[[ "$EXPECTED_SHA" =~ ^[0-9a-fA-F]{64}$ ]] \
    || { echo "❌ yq checksum manifest is missing a valid digest for $YQ_ASSET" >&2; exit 1; }
echo "$EXPECTED_SHA  $YQ_TMP_DIR/$YQ_ASSET" | sha256sum --check --quiet
echo "✅ Checksum verified"

tar -xzf "$YQ_TMP_DIR/$YQ_ASSET" -C "$YQ_TMP_DIR"
[ -f "$YQ_TMP_DIR/$YQ_BINARY" ] \
    || { echo "❌ $YQ_BINARY not found in the downloaded archive" >&2; exit 1; }

if [ -w /usr/local/bin ]; then
    YQ_STAGED_BIN=$(mktemp "${YQ_BIN}.update.XXXXXX")
    install -m 0755 "$YQ_TMP_DIR/$YQ_BINARY" "$YQ_STAGED_BIN"
else
    YQ_STAGED_BIN=$(sudo mktemp "${YQ_BIN}.update.XXXXXX")
    sudo install -m 0755 "$YQ_TMP_DIR/$YQ_BINARY" "$YQ_STAGED_BIN"
fi

"$YQ_STAGED_BIN" --version >/dev/null 2>&1 \
    || { echo "❌ Staged yq binary failed validation" >&2; exit 1; }
if [ -w /usr/local/bin ]; then
    mv -f -- "$YQ_STAGED_BIN" "$YQ_BIN"
else
    sudo mv -f -- "$YQ_STAGED_BIN" "$YQ_BIN"
fi
YQ_STAGED_BIN=""

AFTER_VERSION=$("$YQ_BIN" --version 2>/dev/null | head -1 || true)
echo "✅ yq update complete"
echo "   After:  ${AFTER_VERSION:-version unknown}"
