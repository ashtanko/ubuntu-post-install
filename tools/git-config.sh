#!/bin/bash
set -euo pipefail

# Re-exec under bash if invoked via `sh` (dash mishandles &>, [[ ]], etc.)
if [ -z "${BASH_VERSION:-}" ]; then
    exec /bin/bash "$0" "$@"
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ -f "$REPO_ROOT/.env" ]] && { set -a; source "$REPO_ROOT/.env"; set +a; }

echo "🚀 Applying opinionated git defaults..."

if ! command -v git &>/dev/null; then
    echo "❌ git not installed — run system/base.sh first"
    exit 1
fi

# system/base.sh handles user.name / user.email / init.defaultBranch / core.editor.
# This script layers on workflow-quality settings on top.

set_default() {
    local key="$1" value="$2"
    git config --global "$key" "$value"
    echo "  ✅ $key = $value"
}

echo "🔧 Workflow defaults..."
set_default pull.rebase true
set_default rebase.autoStash true
set_default push.autoSetupRemote true
set_default fetch.prune true
set_default diff.colorMoved zebra
set_default diff.algorithm histogram
set_default merge.conflictStyle zdiff3
set_default rerere.enabled true
set_default core.autocrlf input
set_default core.pager "less -FRX"
set_default branch.sort -committerdate
set_default column.ui auto

echo "🔧 Aliases..."
set_default alias.st "status -sb"
set_default alias.lg "log --oneline --graph --decorate --all -20"
set_default alias.last "log -1 HEAD --stat"
set_default alias.unstage "reset HEAD --"
set_default alias.cleanup "!git branch --merged | grep -vE '^\\s*\\*|^\\s*(main|master|develop)$' | xargs -r -n1 git branch -d"

# GPG signing — only flip on if user opted in via .env and a key exists
if [[ "${ENABLE_GIT_COMMIT_SIGNING:-no}" == "yes" ]]; then
    SIGNING_KEY=$(git config --global --get user.signingkey || true)
    if [ -n "$SIGNING_KEY" ]; then
        set_default commit.gpgsign true
        set_default tag.gpgsign true
        echo "  ✅ Commit signing enabled with key $SIGNING_KEY"
    else
        echo "  ⚠️  ENABLE_GIT_COMMIT_SIGNING=yes but user.signingkey is unset — run system/gpg.sh first"
    fi
fi

# Global gitignore for noise that doesn't belong in any repo
GLOBAL_IGNORE="$HOME/.config/git/ignore"
mkdir -p "$(dirname "$GLOBAL_IGNORE")"
if [ ! -f "$GLOBAL_IGNORE" ]; then
    cat > "$GLOBAL_IGNORE" <<'EOF'
# OS noise
.DS_Store
Thumbs.db
desktop.ini

# Editor / IDE
.idea/
.vscode/
*.swp
*.swo
*~

# Local env
.env
.env.local
*.local

# Build leftovers
*.log
*.tmp
EOF
    echo "  ✅ Wrote $GLOBAL_IGNORE"
else
    echo "  ✅ $GLOBAL_IGNORE already exists (left alone)"
fi
git config --global core.excludesfile "$GLOBAL_IGNORE"

echo ""
echo "✅ Git defaults applied."
echo "💡 Inspect with: git config --global --list | sort"
