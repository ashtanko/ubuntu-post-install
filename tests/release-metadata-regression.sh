#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/release.bash
source "$REPO_ROOT/lib/release.bash"

assert_fields() {
    local expected="$1"
    shift
    local actual
    actual=$(resolve_release_version "$@")
    [[ "$actual" == "$expected" ]] || {
        echo "❌ release metadata mismatch: expected '$expected', got '$actual'"
        exit 1
    }
}

assert_fields 'v1.2.3|1.2.3|false' push '' v1.2.3
assert_fields 'v1.2.3-rc.1+build-meta|1.2.3-rc.1+build-meta|true' \
    workflow_dispatch '1.2.3-rc.1+build-meta' ''
assert_fields 'v1.2.3+build-meta|1.2.3+build-meta|false' \
    workflow_dispatch '1.2.3+build-meta' ''
assert_fields 'v1.2.3+build-x|1.2.3+build-x|false' \
    workflow_dispatch '1.2.3+build-x' ''

for invalid in '1.2.3-01' '01.2.3' '1.2' '1.2.3;echo injected'; do
    if resolve_release_version workflow_dispatch "$invalid" '' >/dev/null 2>&1; then
        echo "❌ invalid semantic version accepted: $invalid"
        exit 1
    fi
done

RELEASE_WORKFLOW="$REPO_ROOT/.github/workflows/release.yml"
grep -q 'source lib/release.bash' "$RELEASE_WORKFLOW" \
    || { echo "❌ release workflow bypasses the tested metadata resolver"; exit 1; }
grep -q 'prerelease:.*steps.ver.outputs.prerelease' "$RELEASE_WORKFLOW" \
    || { echo "❌ release action is not wired to validated prerelease metadata"; exit 1; }
if grep -q 'TAG=.*github.event.inputs.version' "$RELEASE_WORKFLOW"; then
    echo "❌ release workflow interpolates dispatch input into shell source"
    exit 1
fi
for workflow in lint.yml release.yml nightly-health.yml; do
    grep -q 'make check' "$REPO_ROOT/.github/workflows/$workflow" \
        || { echo "❌ $workflow does not enforce the local regression gate"; exit 1; }
done
grep -q 'source lib/release.bash' "$REPO_ROOT/Makefile" \
    || { echo "❌ make tag bypasses the shared SemVer validator"; exit 1; }

echo "✅ release metadata regression checks passed"
