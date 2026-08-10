#!/bin/bash
set -euo pipefail

command -v tmux >/dev/null || { echo "❌ missing: tmux"; exit 1; }
TPM_DIR="${TMUX_PLUGIN_DIR:-$HOME/.tmux/plugins/tpm}"
test -x "$TPM_DIR/tpm" || { echo "❌ missing: TPM at $TPM_DIR"; exit 1; }
test -f "$HOME/.tmux.conf" || { echo "❌ missing: $HOME/.tmux.conf"; exit 1; }
grep -q "tmux-plugins/tpm" "$HOME/.tmux.conf" \
    || { echo "❌ .tmux.conf does not reference TPM"; exit 1; }
# The config must actually parse — a syntax error here would break every new session.
tmux -f "$HOME/.tmux.conf" start-server \; kill-server 2>/dev/null \
    || { echo "❌ .tmux.conf failed to load"; exit 1; }
