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

echo "🚀 Installing Claude Code CLI..."

CLAUDE_CHANNEL="${CLAUDE_CHANNEL:-stable}"
case "$CLAUDE_CHANNEL" in
    stable|latest) ;;
    *)
        echo "❌ Unsupported CLAUDE_CHANNEL: $CLAUDE_CHANNEL (expected stable or latest)" >&2
        exit 2
        ;;
esac

if command -v claude &>/dev/null; then
    echo "✅ Claude Code already installed ($(claude --version 2>/dev/null || echo 'version unknown'))"
    echo "💡 Run 'claude doctor' to check the installation and update status"
    exit 0
fi

echo "📦 Installing repository prerequisites..."
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT
KEY_FILE="$TMP_DIR/claude-code.asc"
GPG_HOME="$TMP_DIR/gnupg"
EXPECTED_FINGERPRINT="31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE"

echo "📥 Downloading and verifying the Anthropic signing key..."
curl -fsSL --retry 3 --retry-all-errors \
    -o "$KEY_FILE" https://downloads.claude.ai/keys/claude-code.asc
mkdir -m 700 "$GPG_HOME"
FINGERPRINT=$(GNUPGHOME="$GPG_HOME" gpg --batch --no-options --show-keys --with-colons \
    "$KEY_FILE" 2>/dev/null | awk -F: '$1 == "fpr" { print $10; exit }')
if [ "$FINGERPRINT" != "$EXPECTED_FINGERPRINT" ]; then
    echo "❌ Anthropic signing key fingerprint mismatch" >&2
    echo "   expected: $EXPECTED_FINGERPRINT" >&2
    echo "   received: ${FINGERPRINT:-missing}" >&2
    exit 1
fi

sudo install -D -o root -g root -m 644 "$KEY_FILE" /etc/apt/keyrings/claude-code.asc
echo "deb [signed-by=/etc/apt/keyrings/claude-code.asc] https://downloads.claude.ai/claude-code/apt/${CLAUDE_CHANNEL} ${CLAUDE_CHANNEL} main" \
    | sudo tee /etc/apt/sources.list.d/claude-code.list >/dev/null

echo "📦 Installing Claude Code from the ${CLAUDE_CHANNEL} channel..."
sudo apt-get update
sudo apt-get install -y claude-code

if ! command -v claude &>/dev/null; then
    echo "❌ Claude Code installation failed or 'claude' is not in PATH" >&2
    exit 1
fi

echo "✅ Claude Code installed successfully ($(claude --version 2>/dev/null || echo 'version unknown'))"
echo "💡 Next step: run 'claude' and follow the browser sign-in prompts"
