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

echo "🚀 Installing gitleaks (secret scanner)..."

# tools/pre-commit-setup.sh wires gitleaks in as a pre-commit hook, but only
# for repos that adopt that config. This installs the binary so any repo can
# be scanned ad hoc — including ones cloned before the hook existed.
if command -v gitleaks &>/dev/null; then
    echo "✅ gitleaks already installed ($(gitleaks version 2>/dev/null | head -1))"
    exit 0
fi

ARCH=$(dpkg --print-architecture)
case "$ARCH" in
    amd64) GL_ARCH="x64"   ;;   # gitleaks names its amd64 asset "x64"
    arm64) GL_ARCH="arm64" ;;
    *) echo "❌ Unsupported architecture: $ARCH"; exit 1 ;;
esac

BIN_DIR="/usr/local/bin"

echo "🔍 Resolving latest gitleaks release..."
GL_VERSION=$(latest_github_tag gitleaks/gitleaks)
GL_NUM=${GL_VERSION#v}
GL_ASSET="gitleaks_${GL_NUM}_linux_${GL_ARCH}.tar.gz"
GL_BASE="https://github.com/gitleaks/gitleaks/releases/download/${GL_VERSION}"

echo "📦 Downloading gitleaks $GL_VERSION..."
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
wget --tries=3 --waitretry=2 -nv --show-progress -O "$TMP/gitleaks.tar.gz" "${GL_BASE}/${GL_ASSET}"

echo "🔒 Verifying checksum..."
GL_CHECKSUMS="$TMP/checksums.txt"
curl -fsSL --retry 3 --retry-all-errors -o "$GL_CHECKSUMS" \
    "${GL_BASE}/gitleaks_${GL_NUM}_checksums.txt"
EXPECTED_SHA=$(awk -v want="$GL_ASSET" '$2 == want {print $1; exit}' "$GL_CHECKSUMS")
[[ "$EXPECTED_SHA" =~ ^[0-9a-fA-F]{64}$ ]] \
    || { echo "❌ gitleaks checksum manifest is missing a valid digest for $GL_ASSET"; exit 1; }
echo "$EXPECTED_SHA  $TMP/gitleaks.tar.gz" | sha256sum --check --quiet
echo "✅ Checksum verified"

tar -xzf "$TMP/gitleaks.tar.gz" -C "$TMP"
[ -f "$TMP/gitleaks" ] || { echo "❌ gitleaks binary not found in tarball"; exit 1; }
sudo install -m 0755 "$TMP/gitleaks" "$BIN_DIR/gitleaks"

if ! command -v gitleaks &>/dev/null; then
    echo "❌ gitleaks installation failed or is not in PATH"
    exit 1
fi

echo ""
echo "✅ gitleaks installed ($(gitleaks version 2>/dev/null | head -1)) → $BIN_DIR/gitleaks"
echo "💡 Scan a working tree:   gitleaks dir ."
echo "💡 Scan full git history: gitleaks git ."
echo "💡 Already wired as a pre-commit hook by tools/pre-commit-setup.sh"
