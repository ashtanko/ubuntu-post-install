#!/bin/bash
set -euo pipefail

# Re-exec under bash if invoked via `sh` (dash mishandles &>, [[ ]], etc.)
if [ -z "${BASH_VERSION:-}" ]; then
    exec /bin/bash "$0" "$@"
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ -f "$REPO_ROOT/.env" ]] && { set -a; source "$REPO_ROOT/.env"; set +a; }

echo "🚀 Installing Java (OpenJDK)..."

SUPPORTED_VERSIONS=(8 11 17 21 25)
DEFAULT_VERSION=21

if [[ -n "${JAVA_VERSION:-}" ]]; then
    VERSION="$JAVA_VERSION"
    echo "🔧 Using JAVA_VERSION=$VERSION from environment"
elif [[ -t 0 ]]; then
    echo "Which OpenJDK version?"
    echo "  1) 8  (LTS, legacy)"
    echo "  2) 11 (LTS)"
    echo "  3) 17 (LTS)"
    echo "  4) 21 (LTS, recommended)"
    echo "  5) 25 (current)"
    echo -n "Choice [4]: "
    read -r choice
    case "${choice:-4}" in
        1) VERSION=8 ;;
        2) VERSION=11 ;;
        3) VERSION=17 ;;
        4|"") VERSION=21 ;;
        5) VERSION=25 ;;
        *) echo "❌ Invalid choice: $choice"; exit 1 ;;
    esac
else
    VERSION="$DEFAULT_VERSION"
    echo "💡 No TTY and JAVA_VERSION unset — defaulting to OpenJDK $VERSION"
fi

valid=0
for v in "${SUPPORTED_VERSIONS[@]}"; do
    [[ "$VERSION" == "$v" ]] && { valid=1; break; }
done
if [[ $valid -eq 0 ]]; then
    echo "❌ Unsupported version: $VERSION (supported: ${SUPPORTED_VERSIONS[*]})"
    exit 1
fi

PKG="openjdk-${VERSION}-jdk"

if dpkg -s "$PKG" &>/dev/null; then
    echo "✅ $PKG already installed"
    java -version
    exit 0
fi

echo "📦 Updating package lists..."
sudo apt update -y

echo "📦 Installing $PKG..."
if ! sudo apt install -y "$PKG"; then
    echo "❌ apt could not install $PKG"
    echo "💡 Your Ubuntu release may not ship this version. Try: apt-cache search '^openjdk-[0-9]+-jdk\$'"
    exit 1
fi

if command -v java &>/dev/null; then
    echo "✅ $PKG installed successfully"
    java -version
    if [[ $(update-alternatives --list java 2>/dev/null | wc -l) -gt 1 ]]; then
        echo ""
        echo "💡 Multiple JDKs detected. Switch the default with:"
        echo "   sudo update-alternatives --config java"
        echo "   sudo update-alternatives --config javac"
    fi
else
    echo "❌ Java installation failed"
    exit 1
fi
