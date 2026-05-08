#!/bin/bash
set -euo pipefail

# Re-exec under bash if invoked via `sh` (dash mishandles &>, [[ ]], etc.)
if [ -z "${BASH_VERSION:-}" ]; then
    exec /bin/bash "$0" "$@"
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ -f "$REPO_ROOT/.env" ]] && { set -a; source "$REPO_ROOT/.env"; set +a; }

OUT="$HOME/system-info-$(date +%Y%m%d-%H%M%S).log"

echo "🚀 Collecting system info → $OUT"

section() { printf '\n=== %s ===\n' "$1"; }

{
    section "DATE / HOST"
    date
    hostname --fqdn 2>/dev/null || hostname

    section "DISTRO"
    if command -v lsb_release &>/dev/null; then lsb_release -a 2>&1 | sed '/^No LSB/d'; fi
    [ -f /etc/os-release ] && cat /etc/os-release

    section "KERNEL / UPTIME"
    uname -a
    uptime

    section "CPU"
    if command -v lscpu &>/dev/null; then lscpu; else grep -E 'model name|cpu cores' /proc/cpuinfo | sort -u; fi

    section "MEMORY"
    free -h

    section "DISK"
    df -hT --total

    section "BLOCK DEVICES"
    if command -v lsblk &>/dev/null; then lsblk -o NAME,SIZE,TYPE,MOUNTPOINT,FSTYPE; fi

    section "GPU"
    if command -v lspci &>/dev/null; then lspci | grep -Ei 'vga|3d|display' || echo "(none detected)"; fi
    if command -v nvidia-smi &>/dev/null; then nvidia-smi || true; fi

    section "NETWORK"
    if command -v ip &>/dev/null; then ip -brief addr; fi

    section "PRIMARY TOOLS"
    for c in git curl wget gcc clang make python3 node npm go rustc java docker code zsh fish; do
        if command -v "$c" &>/dev/null; then
            printf '%-10s %s\n' "$c" "$("$c" --version 2>&1 | head -1)"
        fi
    done

    section "ENV"
    printenv | grep -E '^(LANG|LC_|TZ|SHELL|XDG_|EDITOR|PATH)=' | sort
} > "$OUT" 2>&1

echo "✅ Saved system-info to $OUT"
echo "💡 Attach this file to bug reports or include it in support tickets."
