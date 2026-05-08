#!/bin/bash
set -euo pipefail

# Re-exec under bash if invoked via `sh` (dash mishandles &>, [[ ]], etc.)
if [ -z "${BASH_VERSION:-}" ]; then
    exec /bin/bash "$0" "$@"
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ -f "$REPO_ROOT/.env" ]] && { set -a; source "$REPO_ROOT/.env"; set +a; }

echo "🚀 Setting up SSH key..."

# Install openssh-client if ssh-keygen is missing (minimal Ubuntu containers)
if ! command -v ssh-keygen &>/dev/null; then
    echo "📦 Installing openssh-client..."
    sudo apt update
    sudo apt install -y openssh-client
fi

KEY_FILE="$HOME/.ssh/id_ed25519"

# Resolve email: arg → env var → prompt
if [ -n "${1:-}" ]; then
    EMAIL="$1"
elif [ -n "${GIT_EMAIL:-}" ]; then
    EMAIL="$GIT_EMAIL"
else
    echo -n "📧 Enter your email for the SSH key: "
    read -r EMAIL
fi

if [ -z "$EMAIL" ]; then
    echo "❌ No email provided"
    exit 1
fi

# Generate key only if it doesn't exist
if [ -f "$KEY_FILE" ]; then
    echo "✅ SSH key already exists at $KEY_FILE"
else
    echo "🔑 Generating ed25519 SSH key for $EMAIL..."
    ssh-keygen -t ed25519 -C "$EMAIL" -f "$KEY_FILE"
fi

# Persist ssh-agent autostart in shell configs.
# A previous version of this script ran `eval "$(ssh-agent -s)"` here, but the
# spawned agent died with the script and the ssh-add was silently lost.
# Instead, install an idempotent block in the user's interactive rc files so
# every shell starts (or reuses) an agent and auto-loads the key.
# Single quotes are intentional — vars like `$SSH_AUTH_SOCK` and `$HOME` must be
# evaluated each time the rc file is sourced, not at install time.
# shellcheck disable=SC2016
SSH_AGENT_BLOCK='# ssh-agent autostart (added by ubuntu-setup)
if [ -z "${SSH_AUTH_SOCK:-}" ]; then
    if [ -S "$HOME/.ssh/agent.sock" ] && SSH_AUTH_SOCK="$HOME/.ssh/agent.sock" ssh-add -l >/dev/null 2>&1; then
        export SSH_AUTH_SOCK="$HOME/.ssh/agent.sock"
    else
        rm -f "$HOME/.ssh/agent.sock"
        eval "$(ssh-agent -a "$HOME/.ssh/agent.sock" -s)" >/dev/null
    fi
fi
ssh-add -l >/dev/null 2>&1 || ssh-add -q "$HOME/.ssh/id_ed25519" 2>/dev/null || true'

for RC in "$HOME/.zshrc" "$HOME/.bashrc"; do
    if [ -f "$RC" ] && ! grep -q 'ssh-agent autostart' "$RC"; then
        echo "" >> "$RC"
        printf '%s\n' "$SSH_AGENT_BLOCK" >> "$RC"
        echo "✅ Added ssh-agent autostart to $RC"
    fi
done

# Print public key
echo ""
echo "📋 Your SSH public key (add this to GitHub → Settings → SSH keys):"
echo "---"
cat "${KEY_FILE}.pub"
echo "---"
echo ""
echo "💡 Open a new terminal (or 'source ~/.zshrc') so ssh-agent picks up the key."
echo "💡 Test your GitHub connection with: ssh -T git@github.com"
