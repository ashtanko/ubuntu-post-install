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

OUT="$HOME/system-info-$(date +%Y%m%d-%H%M%S).log"

echo "🚀 Collecting system info → $OUT"

section() { printf '\n=== %s ===\n' "$1"; }

{
    section "DATE / HOST"
    date || echo "(date probe failed)"
    hostname --fqdn 2>/dev/null || hostname || echo "(hostname probe failed)"

    section "DISTRO"
    if command -v lsb_release &>/dev/null; then lsb_release -a 2>&1 | sed '/^No LSB/d' || echo "(lsb_release probe failed)"; fi
    if [ -f /etc/os-release ]; then cat /etc/os-release || echo "(os-release probe failed)"; fi

    section "KERNEL / UPTIME"
    uname -a || echo "(kernel probe failed)"
    uptime || echo "(uptime probe failed)"

    section "CPU"
    if command -v lscpu &>/dev/null; then lscpu || echo "(CPU probe failed)"; else grep -E 'model name|cpu cores' /proc/cpuinfo | sort -u || echo "(CPU probe failed)"; fi

    section "MEMORY"
    free -h || echo "(memory probe failed)"

    section "DISK"
    df -hT --total || echo "(disk probe failed)"

    section "BLOCK DEVICES"
    if command -v lsblk &>/dev/null; then lsblk -o NAME,SIZE,TYPE,MOUNTPOINT,FSTYPE || echo "(block-device probe failed)"; fi

    section "GPU"
    if command -v lspci &>/dev/null; then lspci | grep -Ei 'vga|3d|display' || echo "(none detected)"; fi
    if command -v nvidia-smi &>/dev/null; then nvidia-smi || true; fi

    section "NETWORK"
    if command -v ip &>/dev/null; then ip -brief addr || echo "(network probe failed)"; fi

    section "PRIMARY TOOLS"
    for c in git curl wget gcc clang make python3 node npm go rustc java docker code zsh fish; do
        if command -v "$c" &>/dev/null; then
            version=$("$c" --version 2>&1 | head -1) || version="(version probe failed)"
            printf '%-10s %s\n' "$c" "$version"
        fi
    done

    section "ENV"
    printenv | grep -E '^(LANG|LC_|TZ|SHELL|XDG_|EDITOR|PATH)=' | sort || true
} > "$OUT" 2>&1

echo "✅ Saved system-info to $OUT"
echo "💡 Attach this file to bug reports or include it in support tickets."
