#!/bin/bash
set -euo pipefail
export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
[ -s "$NVM_DIR/nvm.sh" ] || { echo "❌ nvm.sh not found at $NVM_DIR"; exit 1; }
# shellcheck source=/dev/null
. "$NVM_DIR/nvm.sh"
command -v nvm >/dev/null
node --version
npm --version
