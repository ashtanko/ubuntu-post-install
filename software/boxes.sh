#!/bin/bash
set -euo pipefail

# Re-exec under bash if invoked via `sh` (dash mishandles &>, [[ ]], etc.)
if [ -z "${BASH_VERSION:-}" ]; then
    exec /bin/bash "$0" "$@"
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ -f "$REPO_ROOT/.env" ]] && { set -a; source "$REPO_ROOT/.env"; set +a; }

echo "🚀 Installing GNOME Boxes + virt-manager..."

PACKAGES=(gnome-boxes virt-manager)
MISSING=()
for pkg in "${PACKAGES[@]}"; do
    if dpkg -s "$pkg" &>/dev/null; then
        echo "✅ $pkg already installed"
    else
        MISSING+=("$pkg")
    fi
done

if [ ${#MISSING[@]} -gt 0 ]; then
    echo "📦 Installing: ${MISSING[*]}..."
    sudo apt update
    sudo apt install -y "${MISSING[@]}"
fi

echo "✅ Done! Add yourself to the libvirt group if needed:"
echo "     sudo usermod -aG libvirt \"\$USER\""
