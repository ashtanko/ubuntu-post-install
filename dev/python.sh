#!/bin/bash
set -euo pipefail

# Re-exec under bash if invoked via `sh` (dash mishandles &>, [[ ]], etc.)
if [ -z "${BASH_VERSION:-}" ]; then
    exec /bin/bash "$0" "$@"
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ -f "$REPO_ROOT/.env" ]] && { set -a; source "$REPO_ROOT/.env"; set +a; }

echo "🚀 Setting up Python development environment..."

PYENV_DIR="${PYENV_ROOT:-$HOME/.pyenv}"

# 1. Install Python 3 base packages
echo "📦 Installing python3, pip, and venv..."
sudo apt update -y
sudo apt install -y python3 python3-pip python3-venv python3-dev \
    build-essential libssl-dev zlib1g-dev libbz2-dev libreadline-dev \
    libsqlite3-dev libncursesw5-dev xz-utils tk-dev libxml2-dev \
    libxmlsec1-dev libffi-dev liblzma-dev

echo "✅ $(python3 --version)"
echo "✅ pip $(pip3 --version | awk '{print $2}')"

# 2. Install pyenv
if [ -d "$PYENV_DIR" ]; then
    echo "✅ pyenv already installed — updating..."
    git -C "$PYENV_DIR" pull --ff-only
else
    echo "📥 Installing pyenv..."
    git clone https://github.com/pyenv/pyenv.git "$PYENV_DIR"
fi

# 3. Persist pyenv init in shell configs
PYENV_BLOCK="export PYENV_ROOT=\"$PYENV_DIR\"
[[ -d \$PYENV_ROOT/bin ]] && export PATH=\"\$PYENV_ROOT/bin:\$PATH\"
eval \"\$(pyenv init -)\""

for RC in "$HOME/.zshrc" "$HOME/.bashrc"; do
    if [ -f "$RC" ] && ! grep -q 'PYENV_ROOT' "$RC"; then
        {
            echo ""
            echo "# pyenv"
            printf '%s\n' "$PYENV_BLOCK"
        } >> "$RC"
        echo "✅ Added pyenv config to $RC"
    fi
done

# Load pyenv into current session
export PYENV_ROOT="$PYENV_DIR"
export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init -)"

# 4. Install pipx and poetry
if command -v pipx &>/dev/null; then
    echo "✅ pipx already installed"
else
    echo "📦 Installing pipx..."
    sudo apt install -y pipx
    pipx ensurepath
fi

if command -v poetry &>/dev/null; then
    echo "✅ poetry already installed ($(poetry --version))"
else
    echo "📦 Installing poetry via pipx..."
    pipx install poetry
fi

echo ""
echo "✅ Python setup complete!"
echo "   python3: $(python3 --version)"
echo "   pip3:    $(pip3 --version | awk '{print $1,$2}')"
echo "💡 Reload your shell or run: source ~/.zshrc"
