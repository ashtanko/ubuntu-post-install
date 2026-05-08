#!/bin/bash
set -euo pipefail

# Re-exec under bash if invoked via `sh` (dash mishandles &>, [[ ]], etc.)
if [ -z "${BASH_VERSION:-}" ]; then
    exec /bin/bash "$0" "$@"
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ -f "$REPO_ROOT/.env" ]] && { set -a; source "$REPO_ROOT/.env"; set +a; }

echo "🚀 Installing pre-commit framework..."

# pre-commit installs cleanly via pipx; fall back to pip --user if pipx absent
if command -v pre-commit &>/dev/null; then
    echo "✅ pre-commit already installed ($(pre-commit --version))"
else
    if command -v pipx &>/dev/null; then
        echo "📦 Installing pre-commit via pipx..."
        pipx install pre-commit
    else
        echo "📦 pipx not found — installing via apt..."
        sudo apt update
        sudo apt install -y pipx
        pipx ensurepath >/dev/null 2>&1 || true
        pipx install pre-commit
    fi
fi

# Enable pre-commit for any new repo by default — git looks at this template
# whenever it runs `git init` or `git clone`, copying its hooks directory in.
TEMPLATE_DIR="$HOME/.config/git/template"
TEMPLATE_HOOKS="$TEMPLATE_DIR/hooks"
mkdir -p "$TEMPLATE_HOOKS"

# A trivial pre-commit hook that calls into pre-commit if a config exists
PRE_COMMIT_HOOK="$TEMPLATE_HOOKS/pre-commit"
if [ ! -f "$PRE_COMMIT_HOOK" ]; then
    cat > "$PRE_COMMIT_HOOK" <<'HOOK'
#!/bin/sh
# Auto-installed pre-commit shim. Runs `pre-commit run` if the repo has a config.
if [ -f .pre-commit-config.yaml ] && command -v pre-commit >/dev/null 2>&1; then
    exec pre-commit run --hook-stage pre-commit
fi
HOOK
    chmod +x "$PRE_COMMIT_HOOK"
    echo "  ✅ Wrote git template hook: $PRE_COMMIT_HOOK"
fi
git config --global init.templateDir "$TEMPLATE_DIR"

# Drop a starter config users can copy into new projects
TEMPLATE_CONFIG="$HOME/.config/pre-commit/templates/.pre-commit-config.yaml"
mkdir -p "$(dirname "$TEMPLATE_CONFIG")"
if [ ! -f "$TEMPLATE_CONFIG" ]; then
    cat > "$TEMPLATE_CONFIG" <<'YAML'
# Drop this into a new repo as `.pre-commit-config.yaml`, then run:
#   pre-commit install
repos:
  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v5.0.0
    hooks:
      - id: trailing-whitespace
      - id: end-of-file-fixer
      - id: check-yaml
      - id: check-json
      - id: check-merge-conflict
      - id: check-added-large-files
      - id: detect-private-key

  - repo: https://github.com/gitleaks/gitleaks
    rev: v8.21.2
    hooks:
      - id: gitleaks
YAML
    echo "  ✅ Wrote starter config: $TEMPLATE_CONFIG"
fi

echo ""
echo "✅ pre-commit ready."
echo "💡 In any new repo:"
echo "     cp $TEMPLATE_CONFIG .pre-commit-config.yaml"
echo "     pre-commit install"
echo "💡 Existing repos cloned before now also get the shim if you re-init:"
echo "     git init   (idempotent — pulls in the global template)"
