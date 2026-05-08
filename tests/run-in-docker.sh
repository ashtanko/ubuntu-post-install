#!/bin/bash
# Build the test image for a given Ubuntu version, then run every
# manifest-compatible script in its own fresh container.
#
# Usage: tests/run-in-docker.sh [ubuntu_version] [smoke|idempotency] [single_script]
#   ubuntu_version  : 22.04 | 24.04 | 25.04 | 26.04 (default: 24.04)
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

if ! command -v docker >/dev/null 2>&1; then
    echo "❌ docker not found"
    exit 1
fi

# shellcheck source=manifest.sh
source "$REPO_ROOT/tests/manifest.sh"

IMAGE="ubuntu-setup-test:${UBUNTU_VERSION}"

echo "🐳 Building image $IMAGE..."
docker build \
    --build-arg "UBUNTU_VERSION=${UBUNTU_VERSION}" \
    -t "$IMAGE" \
    -f "$REPO_ROOT/tests/Dockerfile" \
    "$REPO_ROOT/tests"

declare -i passed=0 failed=0 skipped=0
declare -a fails=()

run_one() {
    local path="$1" compat="$2" env_vars="$3" verify="$4" reason="$5"

    if [ -n "$ONLY" ] && [ "$path" != "$ONLY" ]; then
        return 0
    fi

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
echo "Passed:   $passed"
echo "Failed:   $failed"
echo "Skipped:  $skipped"
if [ "$failed" -gt 0 ]; then
    echo "Failures:"
    printf "  - %s\n" "${fails[@]}"
    exit 1
fi
