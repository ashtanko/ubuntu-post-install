#!/bin/bash
set -euo pipefail
export RBENV_ROOT="${RBENV_ROOT:-$HOME/.rbenv}"
[ -d "$RBENV_ROOT" ] || { echo "❌ rbenv not at $RBENV_ROOT"; exit 1; }
[ -d "$RBENV_ROOT/plugins/ruby-build" ] || { echo "❌ ruby-build plugin missing"; exit 1; }
export PATH="$RBENV_ROOT/bin:$PATH"
eval "$(rbenv init -)"
command -v rbenv
ruby --version
gem list bundler -i
