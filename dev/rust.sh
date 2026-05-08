#!/bin/bash
set -euo pipefail

# Re-exec under bash if invoked via `sh` (dash mishandles &>, [[ ]], etc.)
if [ -z "${BASH_VERSION:-}" ]; then
    exec /bin/bash "$0" "$@"
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ -f "$REPO_ROOT/.env" ]] && { set -a; source "$REPO_ROOT/.env"; set +a; }

echo "🚀 Installing Rust via rustup..."

RUSTC_VERSION=$("$HOME/.cargo/bin/rustc" --version 2>/dev/null || true)
if echo "$RUSTC_VERSION" | grep -q "^rustc "; then
    echo "✅ Rust already installed ($RUSTC_VERSION)"
    echo "💡 Update with: rustup update"
    exit 0
fi

echo "📥 Downloading and running rustup installer..."
curl --proto '=https' --tlsv1.2 -fsSL https://sh.rustup.rs | sh -s -- -y

# Load cargo into current session
# shellcheck source=/dev/null
. "$HOME/.cargo/env"

# Persist cargo env and PATH in shell configs.
# Single quotes are intentional — we want literal `$HOME` written into the rc files.
# shellcheck disable=SC2016
CARGO_ENV_LINE='[ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"'
# shellcheck disable=SC2016
CARGO_PATH_LINE='export PATH="$HOME/.cargo/bin:$PATH"'
for RC in "$HOME/.zshrc" "$HOME/.bashrc"; do
    if [ -f "$RC" ] && ! grep -q '.cargo/env' "$RC"; then
        {
            echo ""
            echo "# Rust / Cargo"
            echo "$CARGO_ENV_LINE"
            echo "$CARGO_PATH_LINE"
        } >> "$RC"
        echo "✅ Added Cargo env and PATH to $RC"
    fi
done

echo ""
echo "✅ Rust installed!"
echo "   rustc: $(rustc --version)"
echo "   cargo: $(cargo --version)"
echo "💡 Reload your shell or run: source ~/.zshrc"
