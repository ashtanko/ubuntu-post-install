#!/bin/bash
set -euo pipefail

# Re-exec under bash if invoked via `sh` (dash mishandles &>, [[ ]], etc.)
if [ -z "${BASH_VERSION:-}" ]; then
    exec /bin/bash "$0" "$@"
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ -f "$REPO_ROOT/.env" ]] && { set -a; source "$REPO_ROOT/.env"; set +a; }

echo "🚀 Setting up GPG key for git signing..."

# Install gnupg if needed
if ! command -v gpg &>/dev/null; then
    echo "📦 Installing gnupg..."
    sudo apt update
    sudo apt install -y gnupg
fi

# Check if a secret key already exists
EXISTING_KEY=$({ gpg --list-secret-keys --keyid-format=LONG 2>/dev/null || true; } | grep '^sec' | awk '{print $2}' | cut -d'/' -f2 | head -1 || true)

if [ -n "$EXISTING_KEY" ]; then
    echo "✅ GPG key already exists: $EXISTING_KEY"
    KEY_ID="$EXISTING_KEY"
else
    if [ -n "${GIT_NAME:-}" ] && [ -n "${GIT_EMAIL:-}" ]; then
        echo "🔑 Generating GPG key non-interactively for $GIT_NAME <$GIT_EMAIL>..."
        gpg --batch --generate-key <<EOF
Key-Type: RSA
Key-Length: 4096
Subkey-Type: RSA
Subkey-Length: 4096
Name-Real: ${GIT_NAME}
Name-Email: ${GIT_EMAIL}
Expire-Date: 0
%no-protection
%commit
EOF
    else
        echo ""
        echo "💡 Set GIT_NAME and GIT_EMAIL in .env for non-interactive key generation."
        echo "   Recommended settings: RSA 4096, no expiry."
        echo ""
        gpg --full-generate-key
    fi

    KEY_ID=$({ gpg --list-secret-keys --keyid-format=LONG 2>/dev/null || true; } | grep '^sec' | awk '{print $2}' | cut -d'/' -f2 | head -1 || true)
    if [ -z "$KEY_ID" ]; then
        echo "❌ Could not detect generated key ID"
        exit 1
    fi
    echo "✅ GPG key created: $KEY_ID"
fi

# Configure git to use this key for signing
echo "🔧 Configuring git to sign commits with key $KEY_ID..."
git config --global user.signingkey "$KEY_ID"
git config --global commit.gpgsign true

# Persist GPG_TTY so the agent can prompt for passphrase in terminal
GPG_TTY_LINE='export GPG_TTY=$(tty)'
for RC in "$HOME/.zshrc" "$HOME/.bashrc"; do
    if [ -f "$RC" ] && ! grep -q 'GPG_TTY' "$RC"; then
        echo "" >> "$RC"
        echo "# GPG signing" >> "$RC"
        echo "$GPG_TTY_LINE" >> "$RC"
        echo "✅ Added GPG_TTY to $RC"
    fi
done

# Print public key for uploading to GitHub/GitLab
echo ""
echo "📋 Your GPG public key (add this to GitHub → Settings → SSH and GPG keys):"
echo "---"
gpg --armor --export "$KEY_ID"
echo "---"
