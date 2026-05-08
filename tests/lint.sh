#!/bin/bash
set -euo pipefail

if [ -z "${BASH_VERSION:-}" ]; then
    exec /bin/bash "$0" "$@"
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

if ! command -v shellcheck >/dev/null 2>&1; then
    echo "❌ shellcheck not installed. Install: sudo apt install shellcheck"
    exit 1
fi

echo "🔍 Running shellcheck on all .sh files..."
mapfile -t files < <(find . -name '*.sh' -not -path './.git/*' | sort)
echo "  found ${#files[@]} scripts"

fail=0
for f in "${files[@]}"; do
    if ! shellcheck -x "$f"; then
        fail=$((fail + 1))
    fi
done

if [ "$fail" -gt 0 ]; then
    echo "❌ shellcheck failed on $fail file(s)"
    exit 1
fi

echo "✅ shellcheck passed on ${#files[@]} files"
