#!/bin/bash
set -euo pipefail

if [ -z "${BASH_VERSION:-}" ]; then
    exec /bin/bash "$0" "$@"
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

# shellcheck source=manifest.sh
source "$REPO_ROOT/tests/manifest.sh"

mapfile -t found < <(find . -name '*.sh' \
    -not -path './.git/*' \
    -not -path './.omx/*' \
    -not -path './dist/*' \
    -not -path './tests/*' \
    -printf '%P\n' | sort)
mapfile -t listed < <(manifest_paths | sort)

declare -A seen=()
schema_errors=()
home_token="\$HOME/"
braced_home_token="\${HOME}/"
for entry in "${SCRIPTS[@]}"; do
    IFS='|' read -r path compat _env_vars verify reason state_paths extra <<<"$entry"
    if [[ -n "${seen[$path]:-}" ]]; then
        schema_errors+=("duplicate path: $path")
    fi
    seen["$path"]=1
    case "$compat" in
        yes|partial|no) ;;
        *) schema_errors+=("$path: invalid compat '$compat'") ;;
    esac
    if [[ "$compat" == no || "$compat" == partial ]] && [[ -z "$reason" ]]; then
        schema_errors+=("$path: compat=$compat requires a reason")
    fi
    if [[ "$compat" != no ]]; then
        if [[ -z "$verify" ]]; then
            schema_errors+=("$path: runnable entry requires a verifier")
        elif [[ "$verify" =~ ^[[:space:]]*(true|:)[[:space:]]*$ ]]; then
            schema_errors+=("$path: verifier is vacuous")
        elif [[ "$verify" == FILE ]]; then
            verify_file="$REPO_ROOT/tests/verify/${path//\//_}"
            [[ -f "$verify_file" ]] || schema_errors+=("$path: missing verifier file $verify_file")
        fi
    fi
    if [[ -n "$state_paths" ]]; then
        IFS=',' read -ra configured_paths <<<"$state_paths"
        for configured_path in "${configured_paths[@]}"; do
            if [[ "$configured_path" == *'/../'* || "$configured_path" == */.. ]]; then
                schema_errors+=("$path: unsafe state path '$configured_path'")
                continue
            fi
            case "$configured_path" in
                "$home_token"*|"$braced_home_token"*|/etc/*|/opt/*|/usr/local/*|/var/lib/*) ;;
                *) schema_errors+=("$path: unsafe state path '$configured_path'") ;;
            esac
        done
    fi
    [[ -z "$extra" ]] || schema_errors+=("$path: too many manifest fields")
done

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
if [ "${#schema_errors[@]}" -gt 0 ]; then
    echo "❌ Invalid manifest entries:"
    printf '   - %s\n' "${schema_errors[@]}"
    fail=1
fi
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
