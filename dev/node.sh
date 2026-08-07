#!/bin/bash
set -euo pipefail

# Re-exec under bash if invoked via `sh` (dash mishandles &>, [[ ]], etc.)
if [ -z "${BASH_VERSION:-}" ]; then
    exec /bin/bash "$0" "$@"
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ -f "$REPO_ROOT/.env" ]] && { set -a; source "$REPO_ROOT/.env"; set +a; }

echo "🚀 Installing Node.js via NVM..."

NVM_DIR="${NVM_DIR:-$HOME/.nvm}"

# Resolve the newest release tag of a GitHub repo without calling api.github.com —
# unauthenticated API calls are rate-limited per IP and start returning 403 in CI.
# Follows the /releases/latest redirect and reads the tag back out of the URL.
latest_github_tag() {
    local repo="$1" url
    url=$(curl -fsSLI --retry 3 --retry-all-errors -o /dev/null -w '%{url_effective}' "https://github.com/${repo}/releases/latest")
    case "$url" in
        */releases/tag/*) printf '%s\n' "${url##*/releases/tag/}" ;;
        *) echo "❌ Could not resolve latest release for $repo" >&2; return 1 ;;
    esac
}

# Install NVM if not present
if [ -d "$NVM_DIR" ]; then
    echo "✅ NVM already installed"
else
    echo "📦 Fetching latest NVM version..."
    NVM_VERSION=$(latest_github_tag nvm-sh/nvm)
    echo "📥 Installing NVM $NVM_VERSION..."
    curl -fsSL "https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh" | bash
fi

# Load NVM into current session.
# nvm.sh references unset internal vars; relax `set -u` for the whole nvm block.
set +u
export NVM_DIR="$NVM_DIR"
if [ -s "$NVM_DIR/nvm.sh" ]; then
    # shellcheck source=/dev/null
    source "$NVM_DIR/nvm.sh"
else
    echo "❌ NVM looks corrupted: $NVM_DIR/nvm.sh missing"
    echo "💡 Remove $NVM_DIR and re-run this script to reinstall"
    exit 1
fi

# Install latest LTS if no Node version is active
if command -v node &>/dev/null; then
    echo "✅ Node.js already active ($(node -v))"
else
    echo "📦 Installing Node.js LTS..."
    nvm install --lts
    nvm use --lts
fi
set -u

# Persist NVM init block in shell configs (use the actual NVM_DIR, not a hardcoded path)
NVM_BLOCK="export NVM_DIR=\"${NVM_DIR}\"
[ -s \"\$NVM_DIR/nvm.sh\" ] && \\. \"\$NVM_DIR/nvm.sh\"
[ -s \"\$NVM_DIR/bash_completion\" ] && \\. \"\$NVM_DIR/bash_completion\""

for RC in "$HOME/.zshrc" "$HOME/.bashrc"; do
    if [ -f "$RC" ] && ! grep -q 'NVM_DIR' "$RC"; then
        {
            echo ""
            echo "# NVM - Node Version Manager"
            echo "$NVM_BLOCK"
        } >> "$RC"
        echo "✅ Added NVM config to $RC"
    fi
done

echo ""
echo "✅ Node.js setup complete!"
echo "   Node: $(node -v)"
echo "   npm:  $(npm -v)"
echo "💡 Reload your shell or run: source ~/.zshrc"
