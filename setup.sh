#!/bin/bash
set -euo pipefail

# Re-exec under bash if invoked via `sh` (dash mishandles &>, [[ ]], etc.)
if [ -z "${BASH_VERSION:-}" ]; then
    exec /bin/bash "$0" "$@"
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Replaced at release time by .github/workflows/release.yml
VERSION="dev"

case "${1:-}" in
    -v|--version)
        echo "ubuntu-post-install $VERSION"
        exit 0
        ;;
esac

# Load user config — must happen before LOG_FILE is set so SETUP_LOG_FILE is available
[[ -f "$SCRIPT_DIR/.env" ]] && { set -a; source "$SCRIPT_DIR/.env"; set +a; }

LOG_FILE="${SETUP_LOG_FILE:-$HOME/ubuntu-setup.log}"
MARKER_DIR="$HOME/.cache/ubuntu-setup"

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

    log "\n$(date '+%Y-%m-%d %H:%M:%S') ▶ Running: $label"
    if bash "$SCRIPT_DIR/$script" 2>&1 | tee -a "$LOG_FILE"; then
        touch "$marker"
        success "$label complete"
        RESULTS["$label"]="ok"
    else
        fail "$label FAILED (see $LOG_FILE for details)"
        RESULTS["$label"]="failed"
    fi
}

# Menu items: "Label|script/path.sh".
# Each *_ITEMS array is consumed by select_items via `local -n` namerefs (linter
# can't trace these, hence the SC2034 disables on each declaration).
# shellcheck disable=SC2034
declare -a ESSENTIALS_ITEMS=(
    "Swap file|essentials/swap.sh"
    "UFW firewall|essentials/firewall.sh"
    "Unattended security updates|essentials/auto-updates.sh"
    "Locale + timezone|essentials/locale-timezone.sh"
    "GNOME quality-of-life settings|essentials/gnome-settings.sh"
    "System info dump|essentials/system-info.sh"
)
# shellcheck disable=SC2034
declare -a SYSTEM_ITEMS=(
    "Base system (apt upgrade, build tools, git)|system/base.sh"
    "Keyboard remapping (keyd macOS-style)|system/keyboard.sh"
    "GPG key + git signing|system/gpg.sh"
    "SSH key generation|system/ssh.sh"
)
# shellcheck disable=SC2034
declare -a APPS_ITEMS=(
    "Google Chrome|apps/browsers.sh"
    "Guake terminal|apps/guake.sh"
    "Warp terminal|apps/warp.sh"
    "Visual Studio Code|apps/vscode.sh"
)
# shellcheck disable=SC2034
declare -a DEV_ITEMS=(
    "Java (OpenJDK)|dev/java.sh"
    "Docker Engine + Docker Desktop|dev/docker.sh"
    "Flutter SDK + Android|dev/flutter.sh"
    "Node.js (via NVM)|dev/node.sh"
    "Python 3 + pyenv + poetry|dev/python.sh"
    "Rust (via rustup)|dev/rust.sh"
    "Go SDK|dev/go.sh"
)
# shellcheck disable=SC2034
declare -a TOOLS_ITEMS=(
    "Zsh + Oh My Zsh|tools/zsh.sh"
    "Claude Code CLI|tools/claude.sh"
    "CLI tools (bat, fzf, rg, eza, jq, gh...)|tools/cli-tools.sh"
    "Developer Nerd Fonts|tools/fonts.sh"
    "Git config (aliases, defaults, signing)|tools/git-config.sh"
    "pre-commit framework|tools/pre-commit-setup.sh"
    "Backup home (manual; configure in .env)|tools/backup-home.sh"
    "System maintenance (clean caches/logs)|tools/system-maintenance.sh"
)
# shellcheck disable=SC2034
declare -a IDE_ITEMS=(
    "Zed editor|ide/zed.sh"
    "VS Code extensions (from .env)|ide/vscode-extensions.sh"
    "JetBrains Toolbox|ide/jetbrains-toolbox.sh"
    "Neovim (latest)|ide/nvim.sh"
)
# shellcheck disable=SC2034
declare -a AI_ITEMS=(
    "Ollama (local LLMs)|ai/ollama.sh"
    "llama.cpp (build from source)|ai/llama-cpp.sh"
    "Gemini CLI|ai/gemini.sh"
    "Antigravity|ai/antigravity.sh"
    "opencode|ai/opencode.sh"
    "prompt-runner (universal LLM CLI)|ai/prompt-runner.sh"
)
# shellcheck disable=SC2034
declare -a SOFTWARE_ITEMS=(
    "VirtualBox|software/virtualbox.sh"
    "GNOME Boxes + virt-manager|software/boxes.sh"
    "VMware Workstation prereqs|software/vmware.sh"
)

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

select_items ESSENTIALS_ITEMS "🧱 Essentials" QUEUE
select_items SYSTEM_ITEMS     "⚙️  System"   QUEUE
select_items APPS_ITEMS       "🖥️  Apps"     QUEUE
select_items DEV_ITEMS        "🛠️  Dev"      QUEUE
select_items TOOLS_ITEMS      "🔧 Tools"    QUEUE
select_items IDE_ITEMS        "📝 IDE"      QUEUE
select_items AI_ITEMS         "🤖 AI"       QUEUE
select_items SOFTWARE_ITEMS   "💿 Software" QUEUE

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
        ok)      success "$label"; ((OK++)) ;;
        failed)  fail    "$label"; ((FAILED++)) ;;
        skipped) warn    "$label (skipped)"; ((SKIPPED++)) ;;
    esac
done

echo ""
log "  ✅ $OK succeeded  |  ❌ $FAILED failed  |  ⏭️  $SKIPPED skipped"
info "Full log: $LOG_FILE"

[ $FAILED -gt 0 ] && { warn "Some steps failed — check $LOG_FILE"; exit 1; }

echo ""
success "All done! 🎉 You may need to log out and back in for shell/group changes."
