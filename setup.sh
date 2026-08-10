#!/bin/bash
set -euo pipefail

# Re-exec under bash if invoked via `sh` (dash mishandles &>, [[ ]], etc.)
if [ -z "${BASH_VERSION:-}" ]; then
    exec /bin/bash "$0" "$@"
fi

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"

# Replaced at release time by .github/workflows/release.yml
VERSION="dev"

MODE="auto"
RUN_ITEM=""

case "${1:-}" in
    -v|--version)
        echo "ubuntu-post-install $VERSION"
        exit 0
        ;;
    --classic)
        MODE="classic"
        shift
        ;;
    --run-item)
        [ "$#" -eq 2 ] || { echo "usage: ubuntu-post-install --run-item <script>" >&2; exit 2; }
        MODE="run-item"
        RUN_ITEM="$2"
        shift 2
        ;;
    -h|--help)
        cat <<'EOF'
Usage: ubuntu-post-install [--classic | --run-item <script> | --version]

  (no arguments)       launch the full-screen installer when available
  --classic            use the original category-by-category menu
  --run-item <script>  run one catalogued script (used by the TUI)
  --version             print the installed version
EOF
        exit 0
        ;;
    "") ;;
    *)
        echo "unknown option: $1" >&2
        exit 2
        ;;
esac
[ "$#" -eq 0 ] || { echo "unexpected arguments: $*" >&2; exit 2; }

# Load user config before LOG_FILE is set so SETUP_LOG_FILE is available.
CONFIG_HELPER="$SCRIPT_DIR/lib/config.bash"
# shellcheck source=lib/config.bash
source "$CONFIG_HELPER" || { echo "❌ Missing config helper: $CONFIG_HELPER" >&2; exit 1; }
load_config "$SCRIPT_DIR"

LOG_FILE="${SETUP_LOG_FILE:-$HOME/ubuntu-setup.log}"
MARKER_DIR="$HOME/.cache/ubuntu-setup"
CATALOG_FILE="$SCRIPT_DIR/config/catalog.txt"

mkdir -p "$MARKER_DIR"

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

log()     { echo -e "$*" | tee -a "$LOG_FILE"; }
header()  { log "\n${BOLD}${CYAN}═══════════════════════════════════════${RESET}"; log "${BOLD}${CYAN}  $*${RESET}"; log "${BOLD}${CYAN}═══════════════════════════════════════${RESET}"; }
success() { log "${GREEN}  ✅ $*${RESET}"; }
warn()    { log "${YELLOW}  ⚠️  $*${RESET}"; }
fail()    { log "${RED}  ❌ $*${RESET}"; }
info()    { log "${CYAN}  💡 $*${RESET}"; }

declare -A RESULTS

run_script() {
    local label="$1"
    local script="$2"
    local marker
    marker="$MARKER_DIR/$(echo "$script" | tr '/' '_').done"

    if [ -f "$marker" ]; then
        warn "$label already ran — skipping (delete $marker to re-run)"
        RESULTS["$label"]="skipped"
        return
    fi

    if [ -n "${UPI_PROGRESS:-}" ]; then
        log "\n$(date '+%Y-%m-%d %H:%M:%S') ▶ [$UPI_PROGRESS] Running: $label"
    else
        log "\n$(date '+%Y-%m-%d %H:%M:%S') ▶ Running: $label"
    fi
    if bash "$SCRIPT_DIR/$script" 2>&1 | tee -a "$LOG_FILE"; then
        touch "$marker"
        success "$label complete"
        RESULTS["$label"]="ok"
    else
        fail "$label FAILED (see $LOG_FILE for details)"
        RESULTS["$label"]="failed"
    fi
}

declare -a CATALOG_CATEGORY_IDS=()
declare -A CATALOG_CATEGORY_LABELS=()
declare -A CATALOG_CATEGORY_SEEN=()

load_catalog() {
    local category_id category_label label script array_name
    [ -f "$CATALOG_FILE" ] || { fail "Missing installer catalog: $CATALOG_FILE"; exit 1; }

    while IFS='|' read -r category_id category_label label script; do
        [[ -z "$category_id" || "$category_id" == \#* ]] && continue
        [[ "$category_id" =~ ^[a-z][a-z0-9-]*$ ]] || { fail "Invalid category id: $category_id"; exit 1; }
        [[ -n "$category_label" && -n "$label" && -n "$script" ]] \
            || { fail "Invalid catalog row for category: $category_id"; exit 1; }
        [[ "$script" != /* && "$script" != *".."* && -f "$SCRIPT_DIR/$script" ]] \
            || { fail "Invalid catalog script: $script"; exit 1; }

        array_name="CATALOG_ITEMS_${category_id//-/_}"
        if [ -z "${CATALOG_CATEGORY_SEEN[$category_id]:-}" ]; then
            CATALOG_CATEGORY_IDS+=("$category_id")
            CATALOG_CATEGORY_LABELS["$category_id"]="$category_label"
            CATALOG_CATEGORY_SEEN["$category_id"]=yes
            declare -g -a "$array_name=()"
        elif [ "${CATALOG_CATEGORY_LABELS[$category_id]}" != "$category_label" ]; then
            fail "Conflicting labels for catalog category: $category_id"
            exit 1
        fi

        local -n category_items="$array_name"
        category_items+=("$label|$script")
    done < "$CATALOG_FILE"

    [ "${#CATALOG_CATEGORY_IDS[@]}" -gt 0 ] || { fail "Installer catalog is empty"; exit 1; }
}

catalog_label_for_script() {
    local wanted="$1" category_id array_name entry
    for category_id in "${CATALOG_CATEGORY_IDS[@]}"; do
        array_name="CATALOG_ITEMS_${category_id//-/_}"
        local -n lookup_items="$array_name"
        for entry in "${lookup_items[@]}"; do
            if [ "${entry##*|}" = "$wanted" ]; then
                printf '%s\n' "${entry%%|*}"
                return 0
            fi
        done
    done
    return 1
}

load_catalog

if [ "$MODE" = "run-item" ]; then
    if ! RUN_LABEL="$(catalog_label_for_script "$RUN_ITEM")"; then
        fail "Script is not in the installer catalog: $RUN_ITEM"
        exit 2
    fi
    run_script "$RUN_LABEL" "$RUN_ITEM"
    if [ "${RESULTS[$RUN_LABEL]}" = "failed" ]; then
        exit 1
    fi
    exit 0
fi

case "$(uname -m)" in
    x86_64|amd64) TUI_ARCH="amd64" ;;
    aarch64|arm64) TUI_ARCH="arm64" ;;
    *) TUI_ARCH="" ;;
esac
TUI_BIN="$SCRIPT_DIR/bin/ubuntu-post-install-tui-$TUI_ARCH"
if [ "$MODE" = "auto" ] && [ -n "$TUI_ARCH" ] && [ -t 0 ] && [ -t 1 ] \
    && [ "${TERM:-dumb}" != "dumb" ] && [ -x "$TUI_BIN" ]; then
    exec "$TUI_BIN" \
        --root "$SCRIPT_DIR" \
        --catalog "$CATALOG_FILE" \
        --marker-dir "$MARKER_DIR" \
        --log-file "$LOG_FILE" \
        --version "$VERSION"
fi

print_menu() {
    local -n _items=$1
    local category="$2"
    echo -e "\n${BOLD}${CYAN}  $category${RESET}"
    local i=1
    for entry in "${_items[@]}"; do
        local label="${entry%%|*}"
        local script="${entry##*|}"
        local marker
        marker="$MARKER_DIR/$(echo "$script" | tr '/' '_').done"
        local status=""
        [ -f "$marker" ] && status="${GREEN} ✓${RESET}"
        echo -e "    ${BOLD}$i)${RESET} $label$status"
        ((i++))
    done
}

select_items() {
    local -n _src=$1
    local category="$2"
    local -n _dest=$3

    print_menu _src "$category"
    echo ""
    echo -e "  Numbers to select (e.g. ${BOLD}1 3${RESET}), ${BOLD}a${RESET} = all, ${BOLD}n${RESET} = none, Enter = skip category:"
    echo -n "  > "
    read -r input

    if [ "$input" = "a" ]; then
        for entry in "${_src[@]}"; do _dest+=("$entry"); done
    elif [ "$input" != "n" ] && [ -n "$input" ]; then
        for num in $input; do
            if [[ "$num" =~ ^[0-9]+$ ]] && [ "$num" -ge 1 ] && [ "$num" -le "${#_src[@]}" ]; then
                _dest+=("${_src[$((num-1))]}")
            fi
        done
    fi
}

# ── Main ──────────────────────────────────────────────────────────────────────

clear
header "Ubuntu Dev Environment Setup"
log "  Log file: $LOG_FILE"
log "  $(date)"

echo ""
echo -e "  ${BOLD}Select what to install.${RESET} Items marked ${GREEN}✓${RESET} already ran and will be skipped."
echo ""
echo -n "  Press Enter to start the selection..."
read -r

declare -a QUEUE=()

for category_id in "${CATALOG_CATEGORY_IDS[@]}"; do
    items_name="CATALOG_ITEMS_${category_id//-/_}"
    select_items "$items_name" "${CATALOG_CATEGORY_LABELS[$category_id]}" QUEUE
done

if [ ${#QUEUE[@]} -eq 0 ]; then
    warn "Nothing selected — exiting"
    exit 0
fi

echo ""
header "Installing ${#QUEUE[@]} item(s)"
echo ""
echo "  Selected:"
for entry in "${QUEUE[@]}"; do
    echo -e "    • ${entry%%|*}"
done
echo ""
echo -n "  Proceed? [Y/n] "
read -r confirm
[[ "$confirm" =~ ^[Nn]$ ]] && { warn "Aborted"; exit 0; }

for entry in "${QUEUE[@]}"; do
    run_script "${entry%%|*}" "${entry##*|}"
done

# ── Summary ───────────────────────────────────────────────────────────────────
header "Setup Summary"
OK=0; FAILED=0; SKIPPED=0
for label in "${!RESULTS[@]}"; do
    case "${RESULTS[$label]}" in
        ok)      success "$label"; ((++OK)) ;;
        failed)  fail    "$label"; ((++FAILED)) ;;
        skipped) warn    "$label (skipped)"; ((++SKIPPED)) ;;
    esac
done

echo ""
log "  ✅ $OK succeeded  |  ❌ $FAILED failed  |  ⏭️  $SKIPPED skipped"
info "Full log: $LOG_FILE"

[ $FAILED -gt 0 ] && { warn "Some steps failed — check $LOG_FILE"; exit 1; }

echo ""
success "All done! 🎉 You may need to log out and back in for shell/group changes."
