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

CARGO_DIR="${CARGO_HOME:-$HOME/.cargo}"
RUSTUP_BIN="$CARGO_DIR/bin/rustup"
if [ ! -x "$RUSTUP_BIN" ]; then
    echo "⏭️  Rustup is not installed under $CARGO_DIR; skipping Rust update."
    exit 0
fi

RUSTC_BIN="$(dirname "$RUSTUP_BIN")/rustc"
if [ -x "$RUSTC_BIN" ]; then
    BEFORE_VERSION=$("$RUSTC_BIN" --version 2>/dev/null || echo "version unknown")
else
    BEFORE_VERSION="version unknown"
fi
echo "🚀 Updating Rust toolchains..."
echo "   Before: $BEFORE_VERSION"

"$RUSTUP_BIN" update

if [ -x "$RUSTC_BIN" ]; then
    AFTER_VERSION=$("$RUSTC_BIN" --version 2>/dev/null || echo "version unknown")
else
    AFTER_VERSION="version unknown"
fi
echo "✅ Rust update complete"
echo "   After:  $AFTER_VERSION"
