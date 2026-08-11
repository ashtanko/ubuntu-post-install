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

NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
if [ ! -s "$NVM_DIR/nvm.sh" ] || [ ! -d "$NVM_DIR/.git" ]; then
    echo "⏭️  Skipping Node.js update: the repository-managed NVM checkout is not installed."
    exit 0
fi

if ! command -v git >/dev/null 2>&1; then
    echo "❌ git is required to update NVM" >&2
    exit 1
fi
NVM_REMOTE=$(git -C "$NVM_DIR" config --get remote.origin.url 2>/dev/null || true)
case "$NVM_REMOTE" in
    https://github.com/nvm-sh/nvm|https://github.com/nvm-sh/nvm.git) ;;
    *)
        echo "⏭️  Skipping Node.js update: the NVM checkout does not use the official upstream remote."
        exit 0
        ;;
esac
if [ -n "$(git -C "$NVM_DIR" status --porcelain)" ]; then
    echo "❌ Refusing to update NVM: the checkout at $NVM_DIR has uncommitted changes." >&2
    exit 1
fi

NVM_BEFORE_COMMIT=$(git -C "$NVM_DIR" rev-parse HEAD)
NVM_BEFORE_DISPLAY=$(git -C "$NVM_DIR" rev-parse --short HEAD)
restore_nvm_checkout() {
    if git -C "$NVM_DIR" checkout --detach "$NVM_BEFORE_COMMIT"; then
        return 0
    fi
    echo "❌ NVM rollback failed; inspect $NVM_DIR and restore commit $NVM_BEFORE_COMMIT manually." >&2
    return 1
}
BEFORE_VERSION=$(node --version 2>/dev/null || true)
if [ -n "${UPI_NVM_LATEST_TAG:-}" ]; then
    NVM_LATEST_TAG="$UPI_NVM_LATEST_TAG"
else
    GITHUB_HELPER="$REPO_ROOT/lib/github.bash"
    # shellcheck source=lib/github.bash
    source "$GITHUB_HELPER" || { echo "❌ Missing github helper: $GITHUB_HELPER" >&2; exit 1; }
    NVM_LATEST_TAG=$(latest_github_tag nvm-sh/nvm)
fi
[[ "$NVM_LATEST_TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] \
    || { echo "❌ Invalid NVM release tag: $NVM_LATEST_TAG" >&2; exit 1; }

echo "🚀 Updating NVM and Node.js LTS..."
echo "   Before: NVM $NVM_BEFORE_DISPLAY; Node ${BEFORE_VERSION:-not currently active}"
git -C "$NVM_DIR" fetch --depth=1 origin \
    "refs/tags/$NVM_LATEST_TAG:refs/tags/$NVM_LATEST_TAG"
if ! git -C "$NVM_DIR" checkout --detach "$NVM_LATEST_TAG"; then
    if restore_nvm_checkout; then
        echo "❌ NVM update failed; restored the previous checkout" >&2
    else
        echo "❌ NVM update failed and automatic rollback was incomplete" >&2
    fi
    exit 1
fi
if [ ! -s "$NVM_DIR/nvm.sh" ]; then
    if restore_nvm_checkout; then
        echo "❌ Updated NVM checkout is incomplete; restored the previous checkout" >&2
    else
        echo "❌ Updated NVM checkout is incomplete and automatic rollback failed" >&2
    fi
    exit 1
fi

# nvm.sh references unset internal variables, so disable nounset while using it.
set +u
export NVM_DIR
# shellcheck source=/dev/null
source "$NVM_DIR/nvm.sh"
NVM_AFTER_VERSION=$(nvm --version 2>/dev/null || true)
nvm install --lts
nvm alias default 'lts/*'
AFTER_VERSION=$(node --version 2>/dev/null || true)
set -u

echo "✅ NVM and Node.js update complete"
echo "   After:  NVM ${NVM_AFTER_VERSION:-$NVM_LATEST_TAG}; Node ${AFTER_VERSION:-unknown}"
