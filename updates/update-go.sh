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

GO_INSTALL_DIR="${GO_INSTALL_DIR:-/usr/local/go}"
GO_BIN="$GO_INSTALL_DIR/bin/go"

if [ ! -d "$GO_INSTALL_DIR" ] || [ -L "$GO_INSTALL_DIR" ] || [ ! -x "$GO_BIN" ] \
    || ! "$GO_BIN" version &>/dev/null; then
    echo "⏭️  Skipping Go update: a repository-managed SDK was not found at $GO_INSTALL_DIR."
    exit 0
fi

if [ -n "${GO_VERSION:-}" ]; then
    echo "⏭️  Skipping Go update: GO_VERSION is pinned to '$GO_VERSION'."
    exit 0
fi
if [ -n "${GO_ARCHIVE_URL:-}" ] || [ -n "${GO_ARCHIVE_SHA256:-}" ]; then
    echo "⏭️  Skipping Go update: custom archive settings are configured."
    exit 0
fi

if ! command -v realpath >/dev/null 2>&1; then
    echo "❌ realpath is required to validate GO_INSTALL_DIR" >&2
    exit 1
fi
GO_INSTALL_DIR=$(realpath -m "$GO_INSTALL_DIR")
GO_BIN="$GO_INSTALL_DIR/bin/go"
INSTALL_PARENT=$(dirname "$GO_INSTALL_DIR")
case "${GO_INSTALL_DIR##*/}" in
    go|go-*) ;;
    *) echo "❌ Unsafe GO_INSTALL_DIR: expected a basename of go or go-*" >&2; exit 1 ;;
esac
if [ "$GO_INSTALL_DIR" = "/" ] || [ "$INSTALL_PARENT" = "/" ]; then
    echo "❌ Unsafe GO_INSTALL_DIR: refusing a top-level filesystem target" >&2
    exit 1
fi

for REQUIRED_COMMAND in curl python3 dpkg tar sha256sum mktemp; do
    if ! command -v "$REQUIRED_COMMAND" >/dev/null 2>&1; then
        echo "❌ $REQUIRED_COMMAND is required to update Go" >&2
        exit 1
    fi
done

ARCH=$(dpkg --print-architecture)
case "$ARCH" in
    amd64|arm64) ;;
    *) echo "❌ Unsupported Go architecture: $ARCH" >&2; exit 1 ;;
esac

TMP=$(mktemp -d)
STAGE=""
BACKUP=""
declare -a PRIVILEGED=()
cleanup() {
    rm -rf "$TMP"
    if [ -n "$STAGE" ] && "${PRIVILEGED[@]}" test -e "$STAGE" 2>/dev/null; then
        "${PRIVILEGED[@]}" rm -rf -- "$STAGE" || true
    fi
    if [ -n "$BACKUP" ] && "${PRIVILEGED[@]}" test -e "$BACKUP" 2>/dev/null \
        && ! "${PRIVILEGED[@]}" test -e "$GO_INSTALL_DIR" 2>/dev/null; then
        "${PRIVILEGED[@]}" mv "$BACKUP" "$GO_INSTALL_DIR" \
            || echo "⚠️  Previous Go SDK retained at $BACKUP" >&2
    fi
}
trap cleanup EXIT

RELEASES_JSON="$TMP/go-releases.json"
echo "🔍 Resolving the latest stable Go release..."
curl --proto '=https' --tlsv1.2 -fsSL --retry 3 --retry-all-errors \
    -o "$RELEASES_JSON" "https://go.dev/dl/?mode=json"

LATEST_VERSION=$(python3 -c '
import json, sys
for release in json.load(sys.stdin):
    if release.get("stable"):
        print(release["version"])
        raise SystemExit(0)
raise SystemExit(1)
' < "$RELEASES_JSON")
[[ "$LATEST_VERSION" =~ ^go[0-9]+\.[0-9]+(\.[0-9]+)?$ ]] \
    || { echo "❌ go.dev returned an invalid stable version: $LATEST_VERSION" >&2; exit 1; }

BEFORE_VERSION=$("$GO_BIN" version)
CURRENT_VERSION=$(awk '{print $3}' <<< "$BEFORE_VERSION")
if [ "$CURRENT_VERSION" = "$LATEST_VERSION" ]; then
    echo "✅ Go is already current ($BEFORE_VERSION)."
    exit 0
fi

TARBALL="${LATEST_VERSION}.linux-${ARCH}.tar.gz"
EXPECTED_SHA=$(python3 -c '
import json, sys
filename = sys.argv[1]
for release in json.load(sys.stdin):
    for item in release.get("files", []):
        if item.get("filename") == filename:
            print(item.get("sha256", ""))
            raise SystemExit(0)
raise SystemExit(1)
' "$TARBALL" < "$RELEASES_JSON")
[[ "$EXPECTED_SHA" =~ ^[0-9a-fA-F]{64}$ ]] \
    || { echo "❌ go.dev did not publish a valid checksum for $TARBALL" >&2; exit 1; }

echo "🚀 Updating Go..."
echo "   Before: $BEFORE_VERSION"
curl --proto '=https' --tlsv1.2 -fsSL --retry 3 --retry-all-errors \
    -o "$TMP/$TARBALL" "https://go.dev/dl/$TARBALL"
echo "$EXPECTED_SHA  $TMP/$TARBALL" | sha256sum --check --quiet

mkdir -p "$TMP/extract"
tar -C "$TMP/extract" -xzf "$TMP/$TARBALL"
if [ ! -x "$TMP/extract/go/bin/go" ] \
    || ! "$TMP/extract/go/bin/go" version &>/dev/null; then
    echo "❌ Downloaded archive does not contain a working Go SDK" >&2
    exit 1
fi

HOME_CANON=$(realpath -m "$HOME")
case "$INSTALL_PARENT" in
    "$HOME_CANON"|"$HOME_CANON"/*) ;;
    *)
        if [ ! -d "$INSTALL_PARENT" ] || [ ! -w "$INSTALL_PARENT" ]; then
            command -v sudo >/dev/null 2>&1 \
                || { echo "❌ sudo is required to replace $GO_INSTALL_DIR" >&2; exit 1; }
            PRIVILEGED=(sudo)
        fi
        ;;
esac
"${PRIVILEGED[@]}" mkdir -p "$INSTALL_PARENT"
STAGE="$INSTALL_PARENT/.go-update-stage.$$"
BACKUP="$INSTALL_PARENT/.go-update-backup.$$"
if "${PRIVILEGED[@]}" test -e "$STAGE" \
    || "${PRIVILEGED[@]}" test -e "$BACKUP"; then
    echo "❌ Refusing to reuse an existing Go update staging path" >&2
    exit 1
fi

# Finish any cross-filesystem copy before the short atomic rename window.
"${PRIVILEGED[@]}" mv "$TMP/extract/go" "$STAGE"
"${PRIVILEGED[@]}" mv "$GO_INSTALL_DIR" "$BACKUP"
if ! "${PRIVILEGED[@]}" mv "$STAGE" "$GO_INSTALL_DIR"; then
    "${PRIVILEGED[@]}" mv "$BACKUP" "$GO_INSTALL_DIR" || true
    echo "❌ Could not replace the Go SDK; the previous installation was restored" >&2
    exit 1
fi
STAGE=""

if ! AFTER_VERSION=$("$GO_BIN" version 2>/dev/null); then
    FAILED="$INSTALL_PARENT/.go-update-failed.$$"
    if ! "${PRIVILEGED[@]}" mv "$GO_INSTALL_DIR" "$FAILED"; then
        echo "❌ Updated Go SDK failed validation; the previous SDK remains at $BACKUP" >&2
        exit 1
    fi
    STAGE="$FAILED"
    if ! "${PRIVILEGED[@]}" mv "$BACKUP" "$GO_INSTALL_DIR"; then
        echo "❌ Updated Go SDK failed validation and automatic rollback failed; the previous SDK remains at $BACKUP" >&2
        exit 1
    fi
    BACKUP=""
    if "${PRIVILEGED[@]}" rm -rf -- "$FAILED"; then
        STAGE=""
    else
        echo "⚠️  Previous Go SDK was restored, but cleanup of the failed candidate at $FAILED will be retried on exit" >&2
    fi
    echo "❌ Updated Go SDK failed validation; the previous installation was restored" >&2
    exit 1
fi

if ! "${PRIVILEGED[@]}" rm -rf -- "$BACKUP"; then
    echo "⚠️  Go was updated, but the previous SDK could not be removed from $BACKUP" >&2
fi
BACKUP=""
echo "✅ Go update complete"
echo "   After:  $AFTER_VERSION"
