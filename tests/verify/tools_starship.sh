#!/bin/bash
set -euo pipefail

export PATH="$HOME/.local/bin:$PATH"
command -v starship >/dev/null || { echo "❌ missing: starship"; exit 1; }
starship --version >/dev/null
grep -q 'starship init bash' "$HOME/.bashrc" \
    || { echo "❌ Starship Bash initialization is missing"; exit 1; }

if command -v zsh >/dev/null; then
    grep -q 'starship init zsh' "$HOME/.zshrc" \
        || { echo "❌ Starship Zsh initialization is missing"; exit 1; }
fi
if command -v fish >/dev/null; then
    grep -q 'starship init fish' "$HOME/.config/fish/config.fish" \
        || { echo "❌ Starship Fish initialization is missing"; exit 1; }
fi
