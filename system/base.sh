#!/bin/bash
set -euo pipefail

# Re-exec under bash if invoked via `sh` (dash mishandles &>, [[ ]], etc.)
if [ -z "${BASH_VERSION:-}" ]; then
    exec /bin/bash "$0" "$@"
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ -f "$REPO_ROOT/.env" ]] && { set -a; source "$REPO_ROOT/.env"; set +a; }

echo "🚀 Starting base system setup..."

# Update and upgrade
echo "📦 Updating package lists and upgrading system..."
sudo apt update
sudo apt upgrade -y

# Install essential packages
PACKAGES=(gnome-tweaks build-essential git curl wget ca-certificates)
MISSING=()

for pkg in "${PACKAGES[@]}"; do
    if ! dpkg -s "$pkg" &>/dev/null; then
        MISSING+=("$pkg")
    else
        echo "✅ $pkg already installed"
    fi
done

if [ ${#MISSING[@]} -gt 0 ]; then
    echo "📦 Installing: ${MISSING[*]}..."
    sudo apt install -y "${MISSING[@]}"
fi

# Verify key tools
for tool in git curl wget; do
    if command -v "$tool" &>/dev/null; then
        echo "✅ $tool: $($tool --version 2>&1 | head -1)"
    else
        echo "❌ $tool not found after install"
        exit 1
    fi
done

# Configure git identity and defaults from .env
if [ -n "${GIT_NAME:-}" ]; then
    git config --global user.name "$GIT_NAME"
    echo "✅ git user.name = $GIT_NAME"
fi
if [ -n "${GIT_EMAIL:-}" ]; then
    git config --global user.email "$GIT_EMAIL"
    echo "✅ git user.email = $GIT_EMAIL"
fi
if [ -n "${GIT_DEFAULT_BRANCH:-}" ]; then
    git config --global init.defaultBranch "$GIT_DEFAULT_BRANCH"
    echo "✅ git init.defaultBranch = $GIT_DEFAULT_BRANCH"
fi
if [ -n "${GIT_EDITOR:-}" ]; then
    git config --global core.editor "$GIT_EDITOR"
    echo "✅ git core.editor = $GIT_EDITOR"
fi

# GNOME click-to-minimize (only works in a GNOME session)
if command -v gsettings &>/dev/null; then
    echo "🖱️  Enabling click-to-minimize on Dash to Dock..."
    gsettings set org.gnome.shell.extensions.dash-to-dock click-action 'minimize-or-previews' 2>/dev/null \
        && echo "✅ Click-to-minimize enabled" \
        || echo "⚠️  Could not set dash-to-dock (extension may not be active)"
fi

echo "✅ Base system setup complete!"
