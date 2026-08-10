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

echo "🚀 Installing Podman (rootless container engine)..."

CURRENT_USER="$(whoami)"

if command -v podman &>/dev/null; then
    echo "✅ podman already installed ($(podman --version 2>/dev/null))"
else
    echo "📦 Installing podman + uidmap..."
    sudo apt-get update
    sudo apt-get install -y podman uidmap
    echo "✅ podman installed ($(podman --version 2>/dev/null))"
fi

if command -v podman-compose &>/dev/null; then
    echo "✅ podman-compose already installed"
else
    echo "📦 Installing podman-compose..."
    sudo apt-get install -y podman-compose
fi

# Rootless Podman needs a subuid/subgid range for the current user. Modern
# Ubuntu provisions this automatically for interactive users, but it's worth
# checking rather than assuming — and worth NOT silently rewriting
# /etc/subuid or /etc/subgid, since that's system identity mapping, not
# something to change without the user seeing it.
if grep -q "^${CURRENT_USER}:" /etc/subuid 2>/dev/null && grep -q "^${CURRENT_USER}:" /etc/subgid 2>/dev/null; then
    echo "✅ subuid/subgid range already configured for $CURRENT_USER"
else
    echo "⚠️  No subuid/subgid range found for $CURRENT_USER — rootless containers need one."
    echo "💡 Add it with:"
    echo "     sudo usermod --add-subuids 100000-165535 --add-subgids 100000-165535 $CURRENT_USER"
    echo "   then log out and back in."
fi

echo ""
echo "✅ Podman ready!"
echo "💡 Rootless by default: podman run --rm hello-world"
echo "💡 Compose-style workflows: podman-compose up"
echo "💡 Coexists fine with Docker (dev/docker.sh) — different socket, no conflict"
