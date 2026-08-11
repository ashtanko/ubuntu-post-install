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

echo "🚀 Installing .NET SDK..."

# A version the caller pinned is honoured exactly; a defaulted one may fall
# back to whatever the enabled repos actually carry (see below).
DOTNET_VERSION_PINNED="${DOTNET_VERSION:+yes}"
DOTNET_VERSION="${DOTNET_VERSION:-8.0}"
SDK_PACKAGE="dotnet-sdk-${DOTNET_VERSION}"

# `apt-cache policy` prints nothing for an unknown package and
# "Candidate: (none)" for one that exists but cannot be installed.
apt_has_candidate() {
    apt-cache policy "$1" 2>/dev/null | grep -q 'Candidate: [^(]'
}

available_sdk_versions() {
    apt-cache pkgnames dotnet-sdk- 2>/dev/null \
        | sed -n 's/^dotnet-sdk-\([0-9][0-9]*\.[0-9][0-9]*\)$/\1/p' \
        | sort -uV
}

if command -v dotnet &>/dev/null && dotnet --list-sdks 2>/dev/null | grep -q "^${DOTNET_VERSION}\."; then
    echo "✅ .NET SDK $DOTNET_VERSION already installed"
    dotnet --list-sdks | sed 's/^/   /'
    exit 0
fi

# Microsoft's own packages-microsoft-prod.deb wires up both the signed apt
# repo and the keyring in one step. Its config path is versioned per Ubuntu
# release; not every interim release has one yet, so fall back to the
# nearest LTS the same way dev/terraform.sh falls back to an older suite.
CODENAME_VERSION=$(. /etc/os-release && echo "$VERSION_ID")
if [ ! -f /etc/apt/sources.list.d/microsoft-prod.list ]; then
    echo "📦 Adding Microsoft package repository..."
    sudo apt-get update
    sudo apt-get install -y wget ca-certificates

    MS_PROD_DEB=""
    TMP_DEB=""
    # Cleaned on every exit path — a failed `dpkg -i` below would otherwise
    # leave the downloaded .deb behind in /tmp.
    trap 'rm -f "$TMP_DEB"' EXIT
    for CANDIDATE in "$CODENAME_VERSION" 24.04 22.04; do
        URL="https://packages.microsoft.com/config/ubuntu/${CANDIDATE}/packages-microsoft-prod.deb"
        TMP_DEB=$(mktemp --suffix=.deb)
        if wget --tries=3 --waitretry=2 -q -O "$TMP_DEB" "$URL"; then
            MS_PROD_DEB="$TMP_DEB"
            [ "$CANDIDATE" = "$CODENAME_VERSION" ] || echo "⚠️  No Microsoft repo config for Ubuntu $CODENAME_VERSION — using $CANDIDATE instead"
            break
        fi
        rm -f "$TMP_DEB"
    done

    if [ -z "$MS_PROD_DEB" ]; then
        echo "❌ Could not fetch packages-microsoft-prod.deb for Ubuntu $CODENAME_VERSION (or fallbacks)"
        exit 1
    fi

    sudo dpkg -i "$MS_PROD_DEB"
    rm -f "$MS_PROD_DEB"
fi

sudo apt-get update

# Not every Ubuntu release carries every .NET major. Microsoft's repo ships no
# dotnet packages at all for 26.04 (resolute), and Ubuntu's own archive there
# has only 10.0 — so the 8.0 default is simply unavailable. Install the newest
# SDK the enabled repos do offer rather than failing on a stale default.
if ! apt_has_candidate "$SDK_PACKAGE"; then
    AVAILABLE=$(available_sdk_versions | tr '\n' ' ')
    if [ -n "$DOTNET_VERSION_PINNED" ]; then
        echo "❌ $SDK_PACKAGE is not available on Ubuntu $CODENAME_VERSION"
        echo "   Available SDK versions here: ${AVAILABLE:-none}"
        exit 1
    fi

    FALLBACK=$(available_sdk_versions | tail -1)
    if [ -z "$FALLBACK" ]; then
        echo "❌ No dotnet-sdk-* package is available on Ubuntu $CODENAME_VERSION"
        exit 1
    fi

    echo "⚠️  $SDK_PACKAGE is not available on Ubuntu $CODENAME_VERSION — installing dotnet-sdk-$FALLBACK instead"
    DOTNET_VERSION="$FALLBACK"
    SDK_PACKAGE="dotnet-sdk-${DOTNET_VERSION}"

    # Re-check with the resolved version so a re-run exits early instead of
    # handing apt a package it has already installed.
    if command -v dotnet &>/dev/null && dotnet --list-sdks 2>/dev/null | grep -q "^${DOTNET_VERSION}\."; then
        echo "✅ .NET SDK $DOTNET_VERSION already installed"
        dotnet --list-sdks | sed 's/^/   /'
        exit 0
    fi
fi

echo "📦 Installing $SDK_PACKAGE..."
sudo apt-get install -y "$SDK_PACKAGE"

if ! dotnet --list-sdks 2>/dev/null | grep -q "^${DOTNET_VERSION}\."; then
    echo "❌ $SDK_PACKAGE installed but dotnet does not report SDK $DOTNET_VERSION"
    exit 1
fi

echo ""
echo "✅ .NET SDK installed!"
dotnet --list-sdks | sed 's/^/   /'
echo "💡 Install a different major version: DOTNET_VERSION=9.0 bash dev/dotnet.sh"
