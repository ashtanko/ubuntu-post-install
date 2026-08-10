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

echo "🚀 Installing Flameshot (annotated screenshots)..."

if command -v flameshot &>/dev/null; then
    echo "✅ Flameshot already installed ($(flameshot --version 2>/dev/null | head -1))"
else
    echo "📦 Installing flameshot..."
    sudo apt-get update
    sudo apt-get install -y flameshot
    echo "✅ Flameshot installed ($(flameshot --version 2>/dev/null | head -1))"
fi

echo ""
echo "✅ Flameshot ready!"
echo "💡 Interactive capture: flameshot gui"
echo "💡 Bind it to PrtSc in GNOME: Settings → Keyboard → Custom Shortcuts →"
echo "   command 'flameshot gui'. (Clear the built-in PrtSc binding first.)"
echo "💡 On Wayland, run it via the portal: flameshot gui --raw > shot.png"
