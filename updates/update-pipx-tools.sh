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

if ! PIPX_BIN=$(command -v pipx 2>/dev/null); then
    echo "⏭️  Skipping pipx tool updates: pipx is not installed."
    exit 0
fi

PIPX_BEFORE=$("$PIPX_BIN" list --short 2>/dev/null || true)
declare -a INSTALLED_TOOLS=()
declare -a PINNED_TOOLS=()
for TOOL in poetry pre-commit pgcli mycli litecli podman-compose llm litellm; do
    awk -v tool="$TOOL" '$1 == tool { found = 1 } END { exit !found }' <<< "$PIPX_BEFORE" \
        || continue

    case "$TOOL" in
        llm)
            if [ "${LLM_VERSION:-latest}" != "latest" ]; then
                PINNED_TOOLS+=("llm=${LLM_VERSION}")
                continue
            fi
            ;;
        litellm)
            if [ "${LITELLM_VERSION:-latest}" != "latest" ]; then
                PINNED_TOOLS+=("litellm=${LITELLM_VERSION}")
                continue
            fi
            ;;
    esac
    INSTALLED_TOOLS+=("$TOOL")
done

if [ "${#PINNED_TOOLS[@]}" -gt 0 ]; then
    echo "⏭️  Leaving pinned pipx tools unchanged: ${PINNED_TOOLS[*]}"
fi

if [ "${#INSTALLED_TOOLS[@]}" -eq 0 ]; then
    echo "⏭️  Skipping pipx tool updates: no unpinned repository-managed tools are installed."
    exit 0
fi

echo "🚀 Updating installed pipx tools: ${INSTALLED_TOOLS[*]}"
echo "   Before:"
printf '%s\n' "$PIPX_BEFORE" | awk 'NF { print "     " $0 }'

for TOOL in "${INSTALLED_TOOLS[@]}"; do
    "$PIPX_BIN" upgrade "$TOOL"
    if [ "$TOOL" = "litellm" ]; then
        "$PIPX_BIN" runpip litellm install --upgrade \
            'fastapi>=0.136.3,<1.0' \
            'starlette>=1.0.1,<2.0'
    fi
done

PIPX_AFTER=$("$PIPX_BIN" list --short 2>/dev/null || true)
echo "✅ pipx tool updates complete"
echo "   After:"
printf '%s\n' "$PIPX_AFTER" | awk 'NF { print "     " $0 }'
