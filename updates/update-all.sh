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

UPDATES_DIR="$REPO_ROOT/updates"
UPDATE_CATALOG="$UPDATES_DIR/catalog.txt"
if [ ! -r "$UPDATE_CATALOG" ]; then
    echo "❌ Missing updater catalog: $UPDATE_CATALOG" >&2
    exit 1
fi

declare -a UPDATERS=()
declare -A SEEN_UPDATERS=()
while IFS='|' read -r UPDATER_NAME INSTALLERS UPDATE_METHOD EXTRA; do
    [[ -z "$UPDATER_NAME" || "$UPDATER_NAME" == \#* ]] && continue
    if [[ ! "$UPDATER_NAME" =~ ^update-[a-z0-9][a-z0-9-]*\.sh$ ]] \
        || [ -z "$INSTALLERS" ] || [ -z "$UPDATE_METHOD" ] || [ -n "$EXTRA" ]; then
        echo "❌ Invalid updater catalog entry: $UPDATER_NAME" >&2
        exit 1
    fi
    if [ -n "${SEEN_UPDATERS[$UPDATER_NAME]:-}" ]; then
        echo "❌ Duplicate updater catalog entry: $UPDATER_NAME" >&2
        exit 1
    fi
    SEEN_UPDATERS["$UPDATER_NAME"]=1
    [ "$UPDATER_NAME" = "update-all.sh" ] && continue
    if [ ! -f "$UPDATES_DIR/$UPDATER_NAME" ]; then
        echo "❌ Catalogued updater is missing: $UPDATER_NAME" >&2
        exit 1
    fi
    UPDATERS+=("$UPDATES_DIR/$UPDATER_NAME")
done < "$UPDATE_CATALOG"

declare -a FAILED_UPDATERS=()
for UPDATER in "${UPDATERS[@]}"; do
    echo ""
    echo "── $(basename "$UPDATER") ──"
    if ! bash "$UPDATER"; then
        FAILED_UPDATERS+=("$(basename "$UPDATER")")
    fi
done

echo ""
if [ "${#FAILED_UPDATERS[@]}" -gt 0 ]; then
    echo "❌ ${#FAILED_UPDATERS[@]} updater(s) failed: ${FAILED_UPDATERS[*]}" >&2
    exit 1
fi

echo "✅ All ${#UPDATERS[@]} updater(s) completed successfully."
