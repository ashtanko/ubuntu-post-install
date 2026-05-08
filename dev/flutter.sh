#!/bin/bash
set -euo pipefail

# Re-exec under bash if invoked via `sh` (dash mishandles &>, [[ ]], etc.)
if [ -z "${BASH_VERSION:-}" ]; then
    exec /bin/bash "$0" "$@"
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ -f "$REPO_ROOT/.env" ]] && { set -a; source "$REPO_ROOT/.env"; set +a; }

FLUTTER_DEST="${FLUTTER_DIR:-$HOME/development}"
FLUTTER_BIN="$FLUTTER_DEST/flutter/bin"

echo "🚀 Setting up Flutter for Ubuntu..."

# 1. Enable 32-bit architecture (required for Android tools)
echo "🌐 Enabling i386 architecture..."
sudo dpkg --add-architecture i386

# 2. Install system dependencies
echo "📦 Installing system dependencies..."
sudo apt update -y
sudo apt install -y \
    curl git unzip xz-utils zip \
    libglu1-mesa libpulse0 libgl1 \
    libc6:i386 libncurses6:i386 libstdc++6:i386 lib32z1 \
    clang cmake ninja-build pkg-config \
    libgtk-3-dev liblzma-dev libstdc++-12-dev mesa-utils

# 3. Clone Flutter SDK
mkdir -p "$FLUTTER_DEST"
if [ -d "$FLUTTER_DEST/flutter" ]; then
    echo "✅ Flutter SDK already cloned — updating..."
    git -C "$FLUTTER_DEST/flutter" pull --ff-only
else
    echo "📥 Cloning Flutter SDK (stable)..."
    git clone https://github.com/flutter/flutter.git -b stable "$FLUTTER_DEST/flutter"
fi

# 4. Add Flutter to PATH for this session
export PATH="$PATH:$FLUTTER_BIN"

# 5. Persist PATH in shell configs (guard with the full destination path)
PATH_SNIPPET="export PATH=\"\$PATH:$FLUTTER_BIN\""
for RC in "$HOME/.zshrc" "$HOME/.bashrc"; do
    if [ -f "$RC" ] && ! grep -qF "$FLUTTER_BIN" "$RC"; then
        echo "" >> "$RC"
        echo "# Flutter SDK" >> "$RC"
        echo "$PATH_SNIPPET" >> "$RC"
        echo "✅ Added Flutter PATH to $RC"
    fi
done

# 6. Accept Android licenses
echo "📋 Accepting Android licenses (requires Java)..."
if command -v java &>/dev/null; then
    flutter doctor --android-licenses || true
else
    echo "⚠️  Java not found — run dev/java.sh first, then re-run: flutter doctor --android-licenses"
fi

# 7. Run flutter doctor
echo "🏥 Running flutter doctor..."
flutter doctor

echo ""
echo "✅ Flutter setup complete!"
echo "💡 Reload your shell or run: source ~/.zshrc"
