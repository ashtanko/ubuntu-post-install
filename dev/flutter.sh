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

FLUTTER_DEST="${FLUTTER_DIR:-$HOME/development}"
FLUTTER_BIN="$FLUTTER_DEST/flutter/bin"

echo "🚀 Setting up Flutter SDK and Linux desktop dependencies for Ubuntu..."

# 1. Install Flutter SDK and Linux desktop dependencies. Android Studio, the
# Android SDK, an emulator, and device tooling are intentionally out of scope.
echo "📦 Installing Flutter/Linux desktop dependencies..."
sudo apt update -y
sudo apt install -y \
    curl git unzip xz-utils zip \
    libglu1-mesa libpulse0 libgl1 \
    clang cmake ninja-build pkg-config \
    libgtk-3-dev liblzma-dev libstdc++-12-dev mesa-utils

# 2. Clone Flutter SDK
mkdir -p "$FLUTTER_DEST"
if [ -d "$FLUTTER_DEST/flutter" ]; then
    echo "✅ Flutter SDK already cloned — updating..."
    git -C "$FLUTTER_DEST/flutter" pull --ff-only
else
    echo "📥 Cloning Flutter SDK (stable)..."
    git clone https://github.com/flutter/flutter.git -b stable "$FLUTTER_DEST/flutter"
fi

# 3. Add Flutter to PATH for this session
export PATH="$PATH:$FLUTTER_BIN"

# 4. Persist PATH in shell configs (guard with the full destination path)
PATH_SNIPPET="export PATH=\"\$PATH:$FLUTTER_BIN\""
for RC in "$HOME/.zshrc" "$HOME/.bashrc"; do
    if [ -f "$RC" ] && ! grep -qF "$FLUTTER_BIN" "$RC"; then
        {
            echo ""
            echo "# Flutter SDK"
            echo "$PATH_SNIPPET"
        } >> "$RC"
        echo "✅ Added Flutter PATH to $RC"
    fi
done

# 5. Accept Android licenses only when the separately installed Android SDK
# tooling and Java are both available. A failure is reported, never hidden.
ANDROID_STATUS="not configured (Android SDK setup is outside this installer)"
if command -v java &>/dev/null && command -v sdkmanager &>/dev/null; then
    echo "📋 Accepting Android licenses..."
    if flutter doctor --android-licenses; then
        ANDROID_STATUS="licenses accepted"
    else
        ANDROID_STATUS="incomplete (Android license acceptance failed)"
        echo "⚠️  Android setup is incomplete: license acceptance failed."
    fi
else
    echo "ℹ️  Android SDK/license setup skipped; install Java and Android SDK tools separately."
fi

# 6. Run flutter doctor. It may report optional platforms that are not installed.
echo "🏥 Running flutter doctor..."
if ! flutter doctor; then
    echo "⚠️  Flutter doctor reported incomplete optional tooling; review its output above."
fi

echo ""
echo "✅ Flutter SDK and Linux desktop dependencies setup complete!"
echo "ℹ️  Android status: $ANDROID_STATUS"
echo "💡 Reload your shell or run: source ~/.zshrc"
