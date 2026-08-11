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

echo "🚀 Setting up rootless Docker..."

CURRENT_USER="$(id -un)"
USER_ID="$(id -u)"
ROOTLESS_SOCKET="unix:///run/user/${USER_ID}/docker.sock"
ENABLE_LINGER="${DOCKER_ROOTLESS_ENABLE_LINGER:-yes}"

# The whole point is to run the daemon as an unprivileged user. Running the
# setup tool as root would install it for root and defeat the exercise.
if [ "$USER_ID" -eq 0 ]; then
    echo "❌ Run this as your normal user, not as root or via sudo"
    echo "💡 The script calls sudo itself for the few steps that need it"
    exit 1
fi

if ! command -v docker &>/dev/null; then
    echo "❌ Docker CLI not found — install the engine first: bash dev/docker.sh"
    exit 1
fi

# --- Already configured? ---
if [ -f "$HOME/.config/systemd/user/docker.service" ] \
    && systemctl --user is-enabled docker.service &>/dev/null; then
    echo "✅ Rootless Docker already configured for $CURRENT_USER"
    echo "💡 Point the CLI at it: export DOCKER_HOST=$ROOTLESS_SOCKET"
    exit 0
fi

# --- Prerequisites ---
# uidmap supplies newuidmap/newgidmap (the setuid helpers that map the
# subordinate ID range); dbus-user-session keeps the per-user systemd session
# alive so the daemon has something to be supervised by.
echo "📦 Installing rootless prerequisites..."
sudo apt-get update
sudo apt-get install -y uidmap dbus-user-session

# dockerd-rootless-setuptool.sh ships in docker-ce-rootless-extras, which comes
# from Docker's own apt repo — the one dev/docker.sh configures.
if ! command -v dockerd-rootless-setuptool.sh &>/dev/null; then
    if apt-cache policy docker-ce-rootless-extras 2>/dev/null | grep -q 'Candidate: [^(]'; then
        echo "📦 Installing docker-ce-rootless-extras..."
        sudo apt-get install -y docker-ce-rootless-extras
    else
        echo "❌ docker-ce-rootless-extras is not available from the configured apt repos"
        echo "💡 Run 'bash dev/docker.sh' first — it adds Docker's official repository"
        exit 1
    fi
fi

# --- Subordinate UID/GID range ---
# Same posture as dev/podman.sh: report a missing range rather than rewriting
# /etc/subuid and /etc/subgid, which are system identity mapping and not
# something to change without the user seeing it.
if grep -q "^${CURRENT_USER}:" /etc/subuid 2>/dev/null \
    && grep -q "^${CURRENT_USER}:" /etc/subgid 2>/dev/null; then
    echo "✅ subuid/subgid range already configured for $CURRENT_USER"
else
    echo "❌ No subuid/subgid range found for $CURRENT_USER — rootless Docker cannot start without one."
    echo "💡 Add it with:"
    echo "     sudo usermod --add-subuids 100000-165535 --add-subgids 100000-165535 $CURRENT_USER"
    echo "   then log out, back in, and re-run this script."
    exit 1
fi

# --- systemd user session ---
# The setup tool installs a --user unit, so without a running user manager
# there is nothing to install into.
if ! systemctl --user show-environment &>/dev/null; then
    echo "❌ No systemd user session available for $CURRENT_USER"
    echo "💡 This needs a real login session (not a container or a bare SSH 'sudo su')."
    echo "   Log in graphically or over SSH as $CURRENT_USER, then re-run this script."
    exit 1
fi

# The rootful daemon keeps running and keeps its own socket; the two coexist,
# and DOCKER_HOST decides which one the CLI talks to.
if systemctl is-active docker.service &>/dev/null; then
    echo "⚠️  The system-wide Docker daemon is running — it will keep running."
    echo "   Rootless Docker listens on its own socket; DOCKER_HOST selects between them."
fi

echo "🔧 Running dockerd-rootless-setuptool.sh install..."
dockerd-rootless-setuptool.sh install

# Without lingering, the user's systemd session (and the rootless daemon with
# it) is torn down at logout, so containers stop when you close your session.
if [[ "$ENABLE_LINGER" == "no" ]]; then
    echo "⏭️  Skipping linger (DOCKER_ROOTLESS_ENABLE_LINGER=no) — the daemon stops at logout"
elif loginctl show-user "$CURRENT_USER" --property=Linger 2>/dev/null | grep -q 'Linger=yes'; then
    echo "✅ Lingering already enabled for $CURRENT_USER"
else
    echo "🔧 Enabling lingering so the daemon survives logout..."
    sudo loginctl enable-linger "$CURRENT_USER"
fi

# --- Point the CLI at the rootless socket ---
DOCKER_HOST_LINE="export DOCKER_HOST=\"$ROOTLESS_SOCKET\""
for RC in "$HOME/.zshrc" "$HOME/.bashrc"; do
    if [ -f "$RC" ] && ! grep -q 'DOCKER_HOST' "$RC"; then
        {
            echo ""
            echo "# Rootless Docker (added by dev/docker-rootless.sh)"
            printf '%s\n' "$DOCKER_HOST_LINE"
        } >> "$RC"
        echo "✅ Set DOCKER_HOST in $RC"
    fi
done

echo ""
echo "✅ Rootless Docker configured for $CURRENT_USER!"
echo "💡 Activate in this shell: export DOCKER_HOST=$ROOTLESS_SOCKET"
echo "💡 Start/stop the daemon:  systemctl --user start|stop docker"
echo "💡 Talk to the rootful daemon instead: unset DOCKER_HOST"
echo "⚠️  Rootless mode has real limitations: no privileged ports below 1024"
echo "   without extra capabilities, no host networking by default, and"
echo "   overlayfs needs a recent kernel. See docs.docker.com/engine/security/rootless"
