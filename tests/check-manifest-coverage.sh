#!/bin/bash
set -euo pipefail

if [ -z "${BASH_VERSION:-}" ]; then
    exec /bin/bash "$0" "$@"
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

# shellcheck source=manifest.sh
source "$REPO_ROOT/tests/manifest.sh"

mapfile -t found < <(find . -name '*.sh' -not -path './.git/*' -not -path './tests/*' -printf '%P\n' | sort)
mapfile -t listed < <(manifest_paths | sort)

# Detect entries in manifest that no longer exist on disk
stale=()
for p in "${listed[@]}"; do
    if [ ! -f "$REPO_ROOT/$p" ]; then
        stale+=("$p")
    fi
done

# Detect scripts on disk that aren't in the manifest
missing=()
for p in "${found[@]}"; do
    if ! printf '%s\n' "${listed[@]}" | grep -qx "$p"; then
        missing+=("$p")
    fi
done

fail=0
if [ "${#missing[@]}" -gt 0 ]; then
    echo "❌ Scripts missing from tests/manifest.sh:"
    printf '   - %s\n' "${missing[@]}"
    fail=1
fi
if [ "${#stale[@]}" -gt 0 ]; then
    echo "❌ Stale entries in tests/manifest.sh (file no longer exists):"
    printf '   - %s\n' "${stale[@]}"
    fail=1
fi

if [ "$fail" -eq 0 ]; then
    echo "✅ Manifest coverage OK (${#found[@]} scripts, ${#listed[@]} entries)"
fi
exit "$fail"
