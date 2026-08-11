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

PYENV_DIR="${PYENV_ROOT:-$HOME/.pyenv}"
if [ ! -d "$PYENV_DIR/.git" ]; then
    echo "⏭️  Skipping pyenv update: the repository-managed checkout was not found at $PYENV_DIR."
    exit 0
fi
PYENV_REMOTE=$(git -C "$PYENV_DIR" config --get remote.origin.url 2>/dev/null || true)
case "$PYENV_REMOTE" in
    https://github.com/pyenv/pyenv|https://github.com/pyenv/pyenv.git) ;;
    *)
        echo "⏭️  Skipping pyenv update: the checkout does not use the official upstream remote."
        exit 0
        ;;
esac
if [ -n "$(git -C "$PYENV_DIR" status --porcelain)" ]; then
    echo "❌ Refusing to update pyenv: the Git checkout at $PYENV_DIR has uncommitted changes." >&2
    exit 1
fi

BEFORE_COMMIT=$(git -C "$PYENV_DIR" rev-parse --short HEAD)
echo "🚀 Updating pyenv..."
echo "   Before: $BEFORE_COMMIT"
git -C "$PYENV_DIR" pull --ff-only
AFTER_COMMIT=$(git -C "$PYENV_DIR" rev-parse --short HEAD)
echo "✅ pyenv update complete"
echo "   After:  $AFTER_COMMIT"
