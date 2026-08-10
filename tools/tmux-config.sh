#!/bin/bash
set -euo pipefail

# Re-exec under bash if invoked via `sh` (dash mishandles &>, [[ ]], etc.)
if [ -z "${BASH_VERSION:-}" ]; then
    exec /bin/bash "$0" "$@"
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_HELPER="$REPO_ROOT/lib/config.bash"
# shellcheck source=lib/config.bash
source "$CONFIG_HELPER" || { echo "❌ Missing config helper: $CONFIG_HELPER" >&2; exit 1; }
load_config "$REPO_ROOT"

echo "🚀 Setting up tmux (TPM + starter config)..."

# tools/cli-tools.sh installs tmux but leaves it unconfigured — this is the
# equivalent of what zsh.sh does with Oh My Zsh and fish.sh does with Fisher.
if ! command -v tmux &>/dev/null; then
    echo "📦 Installing tmux..."
    sudo apt-get update
    sudo apt-get install -y tmux
fi
echo "✅ tmux installed ($(tmux -V))"

if ! command -v git &>/dev/null; then
    echo "📦 Installing git (required to clone TPM)..."
    sudo apt-get install -y git
fi

# --- TPM (tmux plugin manager) ---
# Deliberately no `git pull` on re-run — same reasoning as dev/python.sh:
# a fetch rewrites .git state every run, breaking idempotency and silently
# moving a pinned TPM out from under the user.
TPM_DIR="${TMUX_PLUGIN_DIR:-$HOME/.tmux/plugins/tpm}"
if [ -d "$TPM_DIR" ]; then
    echo "✅ TPM already installed at $TPM_DIR"
    echo "💡 Update it with: git -C \"$TPM_DIR\" pull --ff-only"
else
    echo "📥 Installing TPM..."
    mkdir -p "$(dirname "$TPM_DIR")"
    git clone https://github.com/tmux-plugins/tpm "$TPM_DIR"
    echo "✅ TPM installed → $TPM_DIR"
fi

# --- Starter config ---
# Written only when absent, so an existing hand-tuned .tmux.conf is never
# clobbered (same posture as ide/nvim.sh's starter init.lua).
TMUX_CONF="$HOME/.tmux.conf"
if [ -f "$TMUX_CONF" ]; then
    echo "✅ $TMUX_CONF already exists (left alone)"
else
    echo "🔧 Writing starter $TMUX_CONF..."
    cat > "$TMUX_CONF" <<'CONF'
# ── Basics ────────────────────────────────────────────────────────────────────
set -g default-terminal "tmux-256color"
set -ag terminal-overrides ",xterm-256color:RGB"
set -g mouse on
set -g base-index 1
setw -g pane-base-index 1
set -g renumber-windows on
set -g history-limit 50000
set -sg escape-time 10
set -g focus-events on

# ── Prefix: Ctrl-a (easier to reach than Ctrl-b) ──────────────────────────────
unbind C-b
set -g prefix C-a
bind C-a send-prefix

# ── Splits that keep the current directory ────────────────────────────────────
bind | split-window -h -c "#{pane_current_path}"
bind - split-window -v -c "#{pane_current_path}"
unbind '"'
unbind %

# ── Vim-style pane navigation ─────────────────────────────────────────────────
bind h select-pane -L
bind j select-pane -D
bind k select-pane -U
bind l select-pane -R

# Reload config
bind r source-file ~/.tmux.conf \; display "Reloaded ~/.tmux.conf"

# ── Copy mode (vi keys) ───────────────────────────────────────────────────────
setw -g mode-keys vi
bind -T copy-mode-vi v send -X begin-selection
bind -T copy-mode-vi y send -X copy-selection-and-cancel

# ── Plugins (install with: prefix + I) ────────────────────────────────────────
set -g @plugin 'tmux-plugins/tpm'
set -g @plugin 'tmux-plugins/tmux-sensible'
set -g @plugin 'tmux-plugins/tmux-resurrect'
set -g @plugin 'tmux-plugins/tmux-continuum'
set -g @plugin 'christoomey/vim-tmux-navigator'

set -g @continuum-restore 'on'

# Keep this line last.
run '~/.tmux/plugins/tpm/tpm'
CONF
    echo "✅ Wrote starter config: $TMUX_CONF"
fi

echo ""
echo "✅ tmux ready!"
echo "💡 Prefix is Ctrl-a (not the default Ctrl-b)"
echo "💡 Start tmux, then press: prefix + I   (capital i) to install the plugins"
echo "💡 Split panes: prefix + |  (vertical)  ·  prefix + -  (horizontal)"
