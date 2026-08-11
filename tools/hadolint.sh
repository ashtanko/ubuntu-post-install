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

echo "🚀 Installing hadolint (Dockerfile linter)..."

if command -v hadolint &>/dev/null; then
    echo "✅ hadolint already installed ($(hadolint --version 2>/dev/null | head -1))"
    exit 0
fi

ARCH=$(dpkg --print-architecture)
case "$ARCH" in
    amd64) HL_ARCH="x86_64" ;;
    arm64) HL_ARCH="arm64"  ;;
    *) echo "❌ Unsupported architecture: $ARCH"; exit 1 ;;
esac

BIN_DIR="/usr/local/bin"

echo "🔍 Resolving latest hadolint release..."
HL_VERSION=$(latest_github_tag hadolint/hadolint)
# Asset names are lowercase ("hadolint-linux-x86_64"), matching what the
# release page publishes — older releases used a capitalised "Linux".
HL_ASSET="hadolint-linux-${HL_ARCH}"
HL_URL="https://github.com/hadolint/hadolint/releases/download/${HL_VERSION}/${HL_ASSET}"

echo "📦 Downloading hadolint $HL_VERSION..."
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
# hadolint publishes no checksum asset to verify against (fetched over TLS from
# github.com); retry protects against a dropped connection, not tampering.
wget --tries=3 --waitretry=2 -nv --show-progress -O "$TMP/hadolint" "$HL_URL"

# With no checksum to check against, at least confirm the download is an ELF
# binary: a truncated transfer or an error page would otherwise be installed
# as an executable and only fail later, at first use.
MAGIC=$(od -An -tx1 -N4 "$TMP/hadolint" | tr -d ' \n')
if [ "$MAGIC" != "7f454c46" ]; then
    echo "❌ Downloaded hadolint is not a Linux executable — refusing to install it"
    exit 1
fi

sudo install -m 0755 "$TMP/hadolint" "$BIN_DIR/hadolint"

if ! command -v hadolint &>/dev/null; then
    echo "❌ hadolint installation failed or is not in PATH"
    exit 1
fi

echo ""
echo "✅ hadolint installed ($(hadolint --version 2>/dev/null | head -1)) → $BIN_DIR/hadolint"
echo "💡 Lint a Dockerfile: hadolint Dockerfile"
echo "💡 Ignore a rule inline: # hadolint ignore=DL3008"
echo "💡 Project-wide config lives in .hadolint.yaml"
echo "💡 tools/pre-commit-setup.sh can run this on every commit"
