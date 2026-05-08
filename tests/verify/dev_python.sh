#!/bin/bash
set -euo pipefail
python3 --version
export PYENV_ROOT="${PYENV_ROOT:-$HOME/.pyenv}"
[ -d "$PYENV_ROOT" ] || { echo "❌ pyenv not at $PYENV_ROOT"; exit 1; }
export PATH="$PYENV_ROOT/bin:$HOME/.local/bin:$PATH"
command -v pyenv
command -v pipx
command -v poetry
