#!/bin/bash
set -euo pipefail
# bat → batcat on Ubuntu, eza or exa, rg → ripgrep
required=(fzf jq htop tmux tree gh)
for cmd in "${required[@]}"; do
    command -v "$cmd" >/dev/null || { echo "❌ missing: $cmd"; exit 1; }
done
command -v rg >/dev/null || command -v ripgrep >/dev/null || { echo "❌ missing ripgrep"; exit 1; }
command -v bat >/dev/null || command -v batcat >/dev/null || { echo "❌ missing bat/batcat"; exit 1; }
command -v eza >/dev/null || command -v exa >/dev/null || { echo "❌ missing eza/exa"; exit 1; }
