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

echo "🚀 Setting up GPG key for git signing..."

# Install gnupg if needed
if ! command -v gpg &>/dev/null; then
    echo "📦 Installing gnupg..."
    sudo apt update
    sudo apt install -y gnupg
fi

KEY_INVENTORY=""
load_secret_key_inventory() {
    local error_output
    if ! error_output=$(gpg --batch --with-colons --fingerprint --list-secret-keys 2>&1); then
        echo "❌ Could not read the GPG secret-key inventory" >&2
        [ -z "$error_output" ] || echo "$error_output" >&2
        return 1
    fi
    KEY_INVENTORY="$error_output"
}

all_secret_fingerprints() {
    awk -F: '
        $1 == "sec" { want_fingerprint = 1; next }
        want_fingerprint && $1 == "fpr" { print toupper($10); want_fingerprint = 0 }
    ' <<< "$KEY_INVENTORY" | sort -u
}

fingerprints_for_key_id() {
    local selector="${1^^}"
    all_secret_fingerprints | awk -v selector="$selector" '
        length($0) >= length(selector) && substr($0, length($0) - length(selector) + 1) == selector
    '
}

fingerprints_for_email() {
    local email="${1,,}"
    awk -F: -v email="$email" '
        $1 == "sec" { fingerprint = ""; next }
        $1 == "fpr" && fingerprint == "" { fingerprint = toupper($10); next }
        $1 == "uid" && fingerprint != "" {
            uid = tolower($10)
            if (uid == email || index(uid, "<" email ">") != 0) print fingerprint
        }
    ' <<< "$KEY_INVENTORY" | sort -u
}

load_secret_key_inventory || exit 1
KEY_ID=""
if [ -n "${GPG_KEY_ID:-}" ]; then
    [[ "$GPG_KEY_ID" =~ ^[0-9a-fA-F]{8,40}$ ]] || {
        echo "❌ GPG_KEY_ID must be an 8- to 40-character hexadecimal key ID or fingerprint"
        exit 1
    }
    mapfile -t MATCHING_KEYS < <(fingerprints_for_key_id "$GPG_KEY_ID")
    if [ "${#MATCHING_KEYS[@]}" -ne 1 ]; then
        echo "❌ GPG_KEY_ID must identify exactly one secret key"
        exit 1
    fi
    KEY_ID="${MATCHING_KEYS[0]}"
elif [ -n "${GIT_EMAIL:-}" ]; then
    mapfile -t MATCHING_KEYS < <(fingerprints_for_email "$GIT_EMAIL")
    if [ "${#MATCHING_KEYS[@]}" -gt 1 ]; then
        echo "❌ Multiple secret keys match $GIT_EMAIL; set GPG_KEY_ID explicitly"
        exit 1
    elif [ "${#MATCHING_KEYS[@]}" -eq 1 ]; then
        KEY_ID="${MATCHING_KEYS[0]}"
    fi
else
    mapfile -t MATCHING_KEYS < <(all_secret_fingerprints)
    if [ "${#MATCHING_KEYS[@]}" -gt 0 ]; then
        echo "❌ Secret keys exist but no selector was configured; set GPG_KEY_ID or GIT_EMAIL"
        exit 1
    fi
fi

if [ -n "$KEY_ID" ]; then
    echo "✅ Selected GPG key: $KEY_ID"
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
        echo "💡 Configure GIT_NAME and GIT_EMAIL for non-interactive key generation."
        echo "   Recommended settings: RSA 4096, no expiry."
        echo ""
        gpg --full-generate-key
    fi

    if [ -n "${GIT_EMAIL:-}" ]; then
        load_secret_key_inventory || exit 1
        mapfile -t MATCHING_KEYS < <(fingerprints_for_email "$GIT_EMAIL")
    else
        load_secret_key_inventory || exit 1
        mapfile -t MATCHING_KEYS < <(all_secret_fingerprints)
    fi
    if [ "${#MATCHING_KEYS[@]}" -ne 1 ]; then
        echo "❌ Could not uniquely identify the generated key; set GPG_KEY_ID explicitly"
        exit 1
    fi
    KEY_ID="${MATCHING_KEYS[0]}"
    echo "✅ GPG key created: $KEY_ID"
fi

# Configure git to use this key for signing
echo "🔧 Configuring git to sign commits with key $KEY_ID..."
git config --global user.signingkey "$KEY_ID"
git config --global commit.gpgsign true

# Persist GPG_TTY so the agent can prompt for passphrase in terminal.
# Single quotes are intentional — `$(tty)` must be evaluated when each shell starts, not now.
# shellcheck disable=SC2016
GPG_TTY_LINE='export GPG_TTY=$(tty)'
for RC in "$HOME/.zshrc" "$HOME/.bashrc"; do
    if [ -f "$RC" ] && ! grep -q 'GPG_TTY' "$RC"; then
        {
            echo ""
            echo "# GPG signing"
            echo "$GPG_TTY_LINE"
        } >> "$RC"
        echo "✅ Added GPG_TTY to $RC"
    fi
done

# Print public key for uploading to GitHub/GitLab
echo ""
echo "📋 Your GPG public key (add this to GitHub → Settings → SSH and GPG keys):"
echo "---"
gpg --armor --export "$KEY_ID"
echo "---"
