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

LLAMA_CPP_DIR="${LLAMA_CPP_DIR:-$HOME/.local/src/llama.cpp}"
LLAMA_BUILD_DIR="$LLAMA_CPP_DIR/build"
LLAMA_BIN_DIR="$LLAMA_BUILD_DIR/bin"
LLAMA_BIN="$LLAMA_BIN_DIR/llama-cli"

if [ ! -d "$LLAMA_CPP_DIR/.git" ] || [ ! -f "$LLAMA_BUILD_DIR/CMakeCache.txt" ]; then
    echo "⏭️  Skipping llama.cpp update: no repository-managed checkout with an existing CMake build was found at $LLAMA_CPP_DIR."
    exit 0
fi
LLAMA_REMOTE=$(git -C "$LLAMA_CPP_DIR" config --get remote.origin.url 2>/dev/null || true)
case "$LLAMA_REMOTE" in
    https://github.com/ggerganov/llama.cpp|https://github.com/ggerganov/llama.cpp.git) ;;
    *)
        echo "⏭️  Skipping llama.cpp update: the checkout does not use the official upstream remote."
        exit 0
        ;;
esac
if [ -n "$(git -C "$LLAMA_CPP_DIR" status --porcelain)" ]; then
    echo "❌ Refusing to update llama.cpp: the Git checkout at $LLAMA_CPP_DIR has uncommitted changes." >&2
    exit 1
fi

BEFORE_COMMIT=$(git -C "$LLAMA_CPP_DIR" rev-parse HEAD)
BEFORE_COMMIT_SHORT=$(git -C "$LLAMA_CPP_DIR" rev-parse --short HEAD)
BEFORE_VERSION=$([ -x "$LLAMA_BIN" ] && "$LLAMA_BIN" --version 2>/dev/null | head -1 || echo "version unknown")
TMP=$(mktemp -d)
HAD_BIN_DIR=0
ROLLBACK_DIR=$(mktemp -d "$LLAMA_BUILD_DIR/.rollback.XXXXXX")
RESTORE_STAGE="$ROLLBACK_DIR/restored-bin"
FAILED_BIN_DIR="$ROLLBACK_DIR/failed-bin"
if [ -d "$LLAMA_BIN_DIR" ]; then
    cp -a "$LLAMA_BIN_DIR" "$TMP/bin"
    HAD_BIN_DIR=1
fi
cleanup() {
    rm -rf "$TMP" "$ROLLBACK_DIR"
}
trap cleanup EXIT

rollback() {
    local rollback_failed=0
    echo "↩️  Restoring llama.cpp to $BEFORE_COMMIT_SHORT..." >&2
    if ! git -C "$LLAMA_CPP_DIR" reset --keep "$BEFORE_COMMIT" >/dev/null; then
        echo "❌ Could not restore the llama.cpp checkout to $BEFORE_COMMIT_SHORT" >&2
        rollback_failed=1
    fi
    if [ "$HAD_BIN_DIR" -eq 1 ]; then
        if ! cp -a "$TMP/bin" "$RESTORE_STAGE"; then
            echo "❌ Could not stage the previous llama.cpp binaries; backup retained at $TMP/bin" >&2
            rollback_failed=1
        elif { [ ! -e "$LLAMA_BIN_DIR" ] || mv "$LLAMA_BIN_DIR" "$FAILED_BIN_DIR"; } \
            && mv "$RESTORE_STAGE" "$LLAMA_BIN_DIR"; then
            rm -rf "$FAILED_BIN_DIR"
        else
            echo "❌ Could not restore the previous llama.cpp binary directory; backup retained at $TMP/bin" >&2
            if [ ! -e "$LLAMA_BIN_DIR" ] && [ -d "$FAILED_BIN_DIR" ]; then
                mv "$FAILED_BIN_DIR" "$LLAMA_BIN_DIR" || true
            fi
            rollback_failed=1
        fi
    elif ! rm -rf "$LLAMA_BIN_DIR"; then
        echo "❌ Could not remove the failed llama.cpp binary directory at $LLAMA_BIN_DIR" >&2
        rollback_failed=1
    fi
    return "$rollback_failed"
}

perform_update() {
    git -C "$LLAMA_CPP_DIR" pull --ff-only || return 1

    # Remove the old executable after backing it up so validation proves this
    # build produced a fresh CLI rather than leaving the previous one in place.
    rm -f "$LLAMA_BIN" || return 1
    cmake --build "$LLAMA_BUILD_DIR" --config Release -j "$(nproc)" || return 1
    [ -x "$LLAMA_BIN" ] || { echo "❌ Rebuild did not produce an executable llama-cli" >&2; return 1; }
    AFTER_VERSION=$("$LLAMA_BIN" --version 2>/dev/null | head -1) || return 1
    [ -n "$AFTER_VERSION" ] || { echo "❌ Rebuilt llama-cli returned no version" >&2; return 1; }
}

echo "🚀 Updating llama.cpp..."
echo "   Before: $BEFORE_COMMIT_SHORT (${BEFORE_VERSION:-version unknown})"
if ! perform_update; then
    if rollback; then
        echo "❌ llama.cpp update failed; the previous checkout and binary were restored" >&2
    else
        # Prevent cleanup from deleting the only remaining binary backup.
        trap - EXIT
        echo "❌ llama.cpp update failed and rollback was incomplete; recovery files remain at $TMP and $ROLLBACK_DIR" >&2
    fi
    exit 1
fi
AFTER_COMMIT=$(git -C "$LLAMA_CPP_DIR" rev-parse --short HEAD)
echo "✅ llama.cpp update complete"
echo "   After:  $AFTER_COMMIT ($AFTER_VERSION)"
