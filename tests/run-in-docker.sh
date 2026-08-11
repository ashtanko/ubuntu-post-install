#!/bin/bash
# Build the test image for a given Ubuntu version, then run every
# manifest-compatible script in its own fresh container.
#
# Usage: tests/run-in-docker.sh [ubuntu_version] [smoke|idempotency] [single_script]
#   ubuntu_version  : 22.04 | 24.04 | 26.04 (default: 24.04)
#   mode            : smoke | idempotency           (default: smoke)
#   single_script   : optional — run only this one path (e.g. dev/node.sh)
set -euo pipefail

if [ -z "${BASH_VERSION:-}" ]; then
    exec /bin/bash "$0" "$@"
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

UBUNTU_VERSION="${1:-24.04}"
MODE="${2:-smoke}"
ONLY="${3:-}"

# shellcheck source=manifest.sh
source "$REPO_ROOT/tests/manifest.sh"

case "$UBUNTU_VERSION" in
    22.04|24.04|26.04) ;;
    *) echo "❌ unsupported Ubuntu version: $UBUNTU_VERSION (expected 22.04, 24.04, or 26.04)"; exit 2 ;;
esac
case "$MODE" in
    smoke|idempotency) ;;
    *) echo "❌ invalid mode: $MODE (expected smoke or idempotency)"; exit 2 ;;
esac
if [[ -n "$ONLY" ]] && ! manifest_lookup "$ONLY" compat >/dev/null; then
    echo "❌ script is not registered in tests/manifest.sh: $ONLY"
    exit 2
fi
if ! command -v docker >/dev/null 2>&1; then
    echo "❌ docker not found"
    exit 1
fi

IMAGE="ubuntu-setup-test:${UBUNTU_VERSION}"

echo "🐳 Building image $IMAGE..."
# CI sets DOCKER_BUILD_CACHE_DIR so the image's apt layer survives between runs;
# without it (the local default) plain `docker build` uses the daemon's own
# layer cache and needs no extra setup. The src/dest split is buildx's
# documented workaround for a local cache that otherwise grows without bound.
CACHE_DIR="${DOCKER_BUILD_CACHE_DIR:-}"
if [ -n "$CACHE_DIR" ] && docker buildx version >/dev/null 2>&1; then
    build_args=(--load --build-arg "UBUNTU_VERSION=${UBUNTU_VERSION}")
    if [ -d "$CACHE_DIR" ]; then
        build_args+=(--cache-from "type=local,src=${CACHE_DIR}")
    fi
    build_args+=(--cache-to "type=local,dest=${CACHE_DIR}.new,mode=max")
    docker buildx build \
        "${build_args[@]}" \
        -t "$IMAGE" \
        -f "$REPO_ROOT/tests/Dockerfile" \
        "$REPO_ROOT/tests"
    rm -rf "$CACHE_DIR"
    mv "${CACHE_DIR}.new" "$CACHE_DIR"
else
    docker build \
        --build-arg "UBUNTU_VERSION=${UBUNTU_VERSION}" \
        -t "$IMAGE" \
        -f "$REPO_ROOT/tests/Dockerfile" \
        "$REPO_ROOT/tests"
fi

declare -i selected=0 passed=0 failed=0 skipped=0
declare -a fails=()

run_one() {
    local path="$1" compat="$2" env_vars="$3" verify="$4" reason="$5" state_paths="$6"

    if [ -n "$ONLY" ] && [ "$path" != "$ONLY" ]; then
        return 0
    fi
    selected+=1

    if [ "$compat" = "no" ]; then
        printf "⏭️  SKIP   %-40s %s\n" "$path" "($reason)"
        skipped+=1
        return 0
    fi

    printf "▶️  RUN    %-40s [%s/%s]\n" "$path" "$UBUNTU_VERSION" "$MODE"

    if docker run --rm \
        -v "$REPO_ROOT":/home/tester/repo:ro \
        -e MANIFEST_SCRIPT="$path" \
        -e MANIFEST_ENV="$env_vars" \
        -e MANIFEST_VERIFY="$verify" \
        -e MANIFEST_MODE="$MODE" \
        -e MANIFEST_STATE_PATHS="$state_paths" \
        "$IMAGE" \
        bash /home/tester/repo/tests/run-script.sh; then
        printf "✅ PASS   %s\n" "$path"
        passed+=1
    else
        printf "❌ FAIL   %s\n" "$path"
        failed+=1
        fails+=("$path")
    fi
}

manifest_iter run_one

echo ""
echo "================ Summary ================"
echo "Image:    $IMAGE"
echo "Mode:     $MODE"
echo "Selected: $selected"
echo "Passed:   $passed"
echo "Failed:   $failed"
echo "Skipped:  $skipped"
if [ "$selected" -eq 0 ] || [ $((passed + failed)) -eq 0 ]; then
    echo "❌ no runnable manifest entries were executed"
    exit 1
fi
if [ "$failed" -gt 0 ]; then
    echo "Failures:"
    printf "  - %s\n" "${fails[@]}"
    exit 1
fi
