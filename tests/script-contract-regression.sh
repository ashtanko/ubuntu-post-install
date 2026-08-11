#!/bin/bash
# Static contract checks that run against EVERY installable script — including
# the ~30 marked `compat=no` in tests/manifest.sh, which no Docker stage ever
# executes. Those scripts are the blind spot where runtime bugs survive, so the
# classes that are cheaply detectable without running anything are caught here.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

failures=0
report() {
    echo "❌ $*" >&2
    ((++failures))
}

mapfile -t scripts < <(find ai apps dev essentials ide mobile software system tools updates vpn \
    -maxdepth 1 -type f -name '*.sh' | sort)
scripts+=(setup.sh install.sh)

# Strip comments and blank lines; what remains is what bash actually runs.
effective_lines() {
    grep -vE '^[[:space:]]*(#|$)' "$1"
}

for script in "${scripts[@]}"; do
    # 1. It has to parse. `bash -n` is the only check that reaches a compat=no
    #    script's syntax at all today.
    bash -n "$script" 2>/dev/null || report "$script: does not parse under bash -n"

    # 2. The final command must not be a bare conditional. `[[ cond ]] && echo …`
    #    as the last line makes the script exit 1 whenever the condition is
    #    false, so setup.sh reports a successful run as FAILED and writes no
    #    completion marker. Regression guard for tools/backup-home.sh.
    last="$(effective_lines "$script" | tail -1)"
    if [[ "$last" =~ ^[[:space:]]*(\[\[|\[|test[[:space:]]) ]] && [[ "$last" != *exit* ]]; then
        report "$script: ends in a bare conditional, so it exits non-zero when that condition is false:
    $last"
    fi

    # 3. `apt-get install` of a repository package must be preceded by an
    #    `apt-get update`. On a fresh or long-idle system /var/lib/apt/lists is
    #    empty or stale and the install dies with "Unable to locate package".
    #    Installing a already-downloaded local .deb needs no index, so those are
    #    exempt. Regression guard for apps/warp.sh, apps/postman.sh, vpn/nord.sh.
    first_install="$(effective_lines "$script" \
        | grep -nE 'apt(-get)? +(-[a-zA-Z-]+ +)*install' \
        | grep -vE 'install +-y +"?\$' \
        | head -1 | cut -d: -f1 || true)"
    if [[ -n "$first_install" ]]; then
        first_update="$(effective_lines "$script" \
            | grep -nE 'apt(-get)? +update' | head -1 | cut -d: -f1 || true)"
        if [[ -z "$first_update" ]]; then
            report "$script: runs apt-get install with no apt-get update anywhere in the script"
        elif (( first_update > first_install )); then
            report "$script: runs apt-get install before its first apt-get update"
        fi
    fi

    # 4. No piping a network fetch into a shell. Every such install must land in
    #    a file first (so a truncated transfer cannot half-execute) and, where
    #    upstream publishes one, be checksum-verified. Lines that merely *print*
    #    an upstream one-liner as a hint are commands starting with echo, so the
    #    anchored match skips them.
    if effective_lines "$script" \
        | grep -qE '^[[:space:]]*(curl|wget)[^|]*\|[[:space:]]*(sudo +)?(ba)?sh\b'; then
        report "$script: pipes a network fetch directly into a shell"
    fi
done

if (( failures > 0 )); then
    echo "" >&2
    echo "❌ $failures script contract violation(s)" >&2
    exit 1
fi

echo "✅ script contracts OK (${#scripts[@]} scripts)"
