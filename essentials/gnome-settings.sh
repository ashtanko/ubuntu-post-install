#!/bin/bash
set -euo pipefail

# Re-exec under bash if invoked via `sh` (dash mishandles &>, [[ ]], etc.)
if [ -z "${BASH_VERSION:-}" ]; then
    exec /bin/bash "$0" "$@"
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ -f "$REPO_ROOT/.env" ]] && { set -a; source "$REPO_ROOT/.env"; set +a; }

echo "🚀 Applying GNOME quality-of-life settings..."

if ! command -v gsettings &>/dev/null; then
    echo "⏭️  gsettings not available — skipping (this isn't a GNOME session)"
    exit 0
fi

# Wrap each in `|| true` so a missing schema (e.g. on minimal GNOME flavors)
# doesn't abort the whole script under `set -e`.
apply() {
    local schema="$1" key="$2" value="$3"
    if gsettings set "$schema" "$key" "$value" 2>/dev/null; then
        echo "  ✅ $schema $key = $value"
    else
        echo "  ⏭️  $schema $key (schema not present)"
    fi
}

echo "🌙 Night light"
apply org.gnome.settings-daemon.plugins.color night-light-enabled true

echo "🖱️  Touchpad"
apply org.gnome.desktop.peripherals.touchpad tap-to-click true
apply org.gnome.desktop.peripherals.touchpad natural-scroll false

echo "🔌 Power"
apply org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type "'nothing'"

echo "🪟 Workspaces"
apply org.gnome.mutter dynamic-workspaces false
apply org.gnome.desktop.wm.preferences num-workspaces 4

echo "⌨️  Keyboard"
apply org.gnome.desktop.input-sources xkb-options "['ctrl:nocaps']"

echo "📁 Nautilus"
apply org.gnome.nautilus.preferences default-folder-viewer "'list-view'"
apply org.gnome.nautilus.preferences show-hidden-files true

echo ""
echo "✅ GNOME settings applied. Some changes only show up in new windows."
