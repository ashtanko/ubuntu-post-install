#!/bin/bash
set -euo pipefail

# Re-exec under bash if invoked via `sh` (dash mishandles &>, [[ ]], etc.)
if [ -z "${BASH_VERSION:-}" ]; then
    exec /bin/bash "$0" "$@"
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ -f "$REPO_ROOT/.env" ]] && { set -a; source "$REPO_ROOT/.env"; set +a; }

echo "🚀 Installing VS Code extensions from \$VSCODE_EXTENSIONS..."

if ! command -v code &>/dev/null; then
    echo "❌ 'code' CLI not found — install VS Code first: bash apps/vscode.sh"
    exit 1
fi

EXTS="${VSCODE_EXTENSIONS:-}"
if [ -z "$EXTS" ]; then
    echo "⚠️  VSCODE_EXTENSIONS is empty in .env — nothing to install"
    echo "💡 Example .env entry:"
    echo "     VSCODE_EXTENSIONS=\"ms-python.python rust-lang.rust-analyzer dbaeumer.vscode-eslint\""
    exit 0
fi

# Read the user's already-installed extensions once
INSTALLED=$(code --list-extensions 2>/dev/null | tr '[:upper:]' '[:lower:]' | sort -u)

INSTALLED_COUNT=0
SKIPPED_COUNT=0
FAILED_COUNT=0

# Iterate whitespace-separated list
read -r -a EXT_ARRAY <<< "$EXTS"
for ext in "${EXT_ARRAY[@]}"; do
    ext_lc=$(echo "$ext" | tr '[:upper:]' '[:lower:]')
    if echo "$INSTALLED" | grep -qx "$ext_lc"; then
        echo "  ✅ $ext (already installed)"
        SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
        continue
    fi
    echo "  📦 Installing $ext..."
    if code --install-extension "$ext" --force >/dev/null 2>&1; then
        echo "  ✅ $ext"
        INSTALLED_COUNT=$((INSTALLED_COUNT + 1))
    else
        echo "  ❌ $ext (failed)"
        FAILED_COUNT=$((FAILED_COUNT + 1))
    fi
done

echo ""
echo "✅ Done — $INSTALLED_COUNT installed · $SKIPPED_COUNT skipped · $FAILED_COUNT failed"
[ "$FAILED_COUNT" -gt 0 ] && exit 1 || exit 0
