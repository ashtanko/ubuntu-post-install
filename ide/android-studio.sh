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

echo "🚀 Installing Android Studio..."

# dev/flutter.sh deliberately leaves Android Studio, the Android SDK, an
# emulator, and device tooling out of scope. This script is that other half.
if snap list android-studio &>/dev/null; then
    INSTALLED_VERSION=$(snap list android-studio 2>/dev/null | awk 'NR==2 {print $2}')
    echo "✅ Android Studio already installed (${INSTALLED_VERSION:-unknown version})"
    echo "💡 Update with: sudo snap refresh android-studio"
    exit 0
fi

if ! command -v snap &>/dev/null; then
    echo "📦 Installing snapd..."
    sudo apt-get update
    sudo apt-get install -y snapd
fi

echo "📦 Installing android-studio via snap (--classic: needs full filesystem access for the SDK/emulator)..."
sudo snap install android-studio --classic

if ! snap list android-studio &>/dev/null; then
    echo "❌ Android Studio installation failed"
    exit 1
fi

echo ""
echo "✅ Android Studio installed!"
echo "💡 Launch it from the application menu, or run: android-studio"
echo "💡 First run walks you through the Android SDK/emulator setup wizard."
echo "💡 For device access over USB, make sure your user is in the 'dialout' and 'plugdev' groups"
echo "   (system/user-groups.sh does this automatically)."
echo "💡 Already run dev/flutter.sh? Re-run 'flutter doctor' afterwards to pick up the SDK."
