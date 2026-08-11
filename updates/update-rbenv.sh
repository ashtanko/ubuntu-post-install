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

RBENV_DIR="${RBENV_ROOT:-$HOME/.rbenv}"
RUBY_BUILD_DIR="$RBENV_DIR/plugins/ruby-build"

if [ ! -d "$RBENV_DIR/.git" ] || [ ! -d "$RUBY_BUILD_DIR/.git" ]; then
    echo "⏭️  Skipping rbenv update: the repository-managed rbenv and ruby-build checkouts were not both found under $RBENV_DIR."
    exit 0
fi

RBENV_REMOTE=$(git -C "$RBENV_DIR" config --get remote.origin.url 2>/dev/null || true)
RUBY_BUILD_REMOTE=$(git -C "$RUBY_BUILD_DIR" config --get remote.origin.url 2>/dev/null || true)
case "$RBENV_REMOTE" in
    https://github.com/rbenv/rbenv|https://github.com/rbenv/rbenv.git) ;;
    *)
        echo "⏭️  Skipping rbenv update: the checkout does not use the official upstream remote."
        exit 0
        ;;
esac
case "$RUBY_BUILD_REMOTE" in
    https://github.com/rbenv/ruby-build|https://github.com/rbenv/ruby-build.git) ;;
    *)
        echo "⏭️  Skipping rbenv update: ruby-build does not use the official upstream remote."
        exit 0
        ;;
esac

for REPOSITORY in "$RBENV_DIR" "$RUBY_BUILD_DIR"; do
    if [ -n "$(git -C "$REPOSITORY" status --porcelain)" ]; then
        echo "❌ Refusing to update $(basename "$REPOSITORY"): the Git checkout at $REPOSITORY has uncommitted changes." >&2
        exit 1
    fi
done

RBENV_BEFORE=$(git -C "$RBENV_DIR" rev-parse --short HEAD)
RUBY_BUILD_BEFORE=$(git -C "$RUBY_BUILD_DIR" rev-parse --short HEAD)
echo "🚀 Updating rbenv and ruby-build..."
echo "   Before: rbenv $RBENV_BEFORE; ruby-build $RUBY_BUILD_BEFORE"
git -C "$RBENV_DIR" pull --ff-only
git -C "$RUBY_BUILD_DIR" pull --ff-only
RBENV_AFTER=$(git -C "$RBENV_DIR" rev-parse --short HEAD)
RUBY_BUILD_AFTER=$(git -C "$RUBY_BUILD_DIR" rev-parse --short HEAD)
echo "✅ rbenv and ruby-build update complete"
echo "   After:  rbenv $RBENV_AFTER; ruby-build $RUBY_BUILD_AFTER"
