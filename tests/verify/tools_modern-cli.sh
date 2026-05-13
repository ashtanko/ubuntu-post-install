#!/bin/bash
set -euo pipefail
# Tools from apt + GitHub releases. zoxide lands in ~/.local/bin, so add it to PATH for the check.
export PATH="$HOME/.local/bin:$PATH"
required=(lazygit delta btop direnv hyperfine dust tldr zoxide)
for cmd in "${required[@]}"; do
    command -v "$cmd" >/dev/null || { echo "❌ missing: $cmd"; exit 1; }
done
# fd-find ships as `fdfind`; modern-cli.sh symlinks fd → fdfind into ~/.local/bin
command -v fd >/dev/null || command -v fdfind >/dev/null || { echo "❌ missing fd/fdfind"; exit 1; }
