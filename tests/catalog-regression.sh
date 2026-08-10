#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CATALOG="$REPO_ROOT/config/catalog.txt"
# shellcheck source=manifest.sh
source "$REPO_ROOT/tests/manifest.sh"

fail() {
    echo "❌ $*" >&2
    exit 1
}

[ -f "$CATALOG" ] || fail "missing installer catalog"

declare -A seen_scripts=()
declare -A seen_categories=()
catalog_paths=()
category_count=0
item_count=0

while IFS='|' read -r category_id category_label label script extra; do
    [[ -z "$category_id" || "$category_id" == \#* ]] && continue
    [[ "$category_id" =~ ^[a-z][a-z0-9-]*$ ]] || fail "invalid category id: $category_id"
    [[ -n "$category_label" && -n "$label" && -n "$script" && -z "$extra" ]] \
        || fail "invalid catalog row for category: $category_id"
    [[ "$script" != /* && "$script" != *'/../'* && "$script" != ../* ]] \
        || fail "unsafe catalog path: $script"
    [ -f "$REPO_ROOT/$script" ] || fail "catalog script does not exist: $script"
    [[ -z "${seen_scripts[$script]:-}" ]] || fail "duplicate catalog script: $script"
    manifest_lookup "$script" compat >/dev/null || fail "catalog script missing from test manifest: $script"
    seen_scripts["$script"]=1
    catalog_paths+=("$script")
    ((++item_count))
    if [[ -z "${seen_categories[$category_id]:-}" ]]; then
        seen_categories["$category_id"]="$category_label"
        ((++category_count))
    elif [[ "${seen_categories[$category_id]}" != "$category_label" ]]; then
        fail "conflicting labels for category: $category_id"
    fi
done < "$CATALOG"

mapfile -t expected_paths < <(
    cd "$REPO_ROOT"
    find ai apps dev essentials ide software system tools vpn \
        -maxdepth 1 -type f -name '*.sh' -print | sort
)
mapfile -t actual_paths < <(printf '%s\n' "${catalog_paths[@]}" | sort)

if [ "${expected_paths[*]}" != "${actual_paths[*]}" ]; then
    diff -u <(printf '%s\n' "${expected_paths[@]}") <(printf '%s\n' "${actual_paths[@]}") || true
    fail "installer catalog does not cover every selectable script"
fi

echo "✅ installer catalog OK ($item_count items, $category_count categories)"
