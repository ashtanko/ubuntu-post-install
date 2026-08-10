#!/bin/bash
set -euo pipefail

command -v fish >/dev/null || { echo "❌ missing: fish"; exit 1; }
test -f "$HOME/.config/fish/functions/fisher.fish" \
    || { echo "❌ missing: Fisher plugin manager"; exit 1; }
fish -c 'type -q fisher' || { echo "❌ Fisher command is unavailable"; exit 1; }
