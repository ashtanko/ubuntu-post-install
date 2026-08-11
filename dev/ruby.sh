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

echo "🚀 Setting up Ruby development environment..."

RBENV_DIR="${RBENV_ROOT:-$HOME/.rbenv}"

# 1. ruby-build's native extension toolchain
echo "📦 Installing Ruby build dependencies..."
sudo apt-get update
sudo apt-get install -y build-essential libssl-dev libreadline-dev zlib1g-dev \
    libyaml-dev libffi-dev libgdbm-dev libncurses5-dev autoconf bison

# 2. Install rbenv + ruby-build
# Deliberately no `git pull` on re-run — see dev/python.sh for why: a fetch
# rewrites .git/FETCH_HEAD/.git/ORIG_HEAD every run, breaking idempotency
# and silently moving a pinned rbenv/ruby-build out from under the user.
if [ -d "$RBENV_DIR" ]; then
    echo "✅ rbenv already installed"
    echo "💡 Update it with: git -C \"$RBENV_DIR\" pull --ff-only"
else
    echo "📥 Installing rbenv..."
    git clone https://github.com/rbenv/rbenv.git "$RBENV_DIR"
fi

RUBY_BUILD_DIR="$RBENV_DIR/plugins/ruby-build"
if [ -d "$RUBY_BUILD_DIR" ]; then
    echo "✅ ruby-build plugin already installed"
else
    echo "📥 Installing ruby-build plugin..."
    git clone https://github.com/rbenv/ruby-build.git "$RUBY_BUILD_DIR"
fi

# 3. Persist rbenv init in shell configs
RBENV_BLOCK="export RBENV_ROOT=\"$RBENV_DIR\"
[[ -d \$RBENV_ROOT/bin ]] && export PATH=\"\$RBENV_ROOT/bin:\$PATH\"
eval \"\$(rbenv init -)\""

for RC in "$HOME/.zshrc" "$HOME/.bashrc"; do
    if [ -f "$RC" ] && ! grep -q 'RBENV_ROOT' "$RC"; then
        {
            echo ""
            echo "# rbenv"
            printf '%s\n' "$RBENV_BLOCK"
        } >> "$RC"
        echo "✅ Added rbenv config to $RC"
    fi
done

# Load rbenv into current session
export RBENV_ROOT="$RBENV_DIR"
export PATH="$RBENV_ROOT/bin:$PATH"
eval "$(rbenv init -)"

# 4. Install a Ruby version (RUBY_VERSION pins it; otherwise the newest
# non-preview release ruby-build knows about — entries with a "-" suffix
# are dev/preview/rc builds, e.g. "3.4.0-preview1").
RUBY_TARGET_VERSION="${RUBY_VERSION:-}"
if [ -z "$RUBY_TARGET_VERSION" ]; then
    echo "🔍 Resolving latest stable Ruby version..."
    RUBY_TARGET_VERSION=$(rbenv install -l | sed 's/^ *//' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | tail -1)
fi

if [ -z "$RUBY_TARGET_VERSION" ]; then
    echo "❌ Could not determine a Ruby version to install"
    exit 1
fi

if rbenv versions --bare 2>/dev/null | grep -qx "$RUBY_TARGET_VERSION"; then
    echo "✅ Ruby $RUBY_TARGET_VERSION already installed"
else
    echo "📥 Building Ruby $RUBY_TARGET_VERSION (this compiles from source — a few minutes)..."
    rbenv install --skip-existing "$RUBY_TARGET_VERSION"
fi

rbenv global "$RUBY_TARGET_VERSION"
rbenv rehash

# 5. bundler
if rbenv exec gem list bundler -i &>/dev/null; then
    echo "✅ bundler already installed"
else
    echo "📦 Installing bundler..."
    rbenv exec gem install bundler
    rbenv rehash
fi

echo ""
echo "✅ Ruby setup complete!"
echo "   $(rbenv exec ruby --version)"
echo "   $(rbenv exec gem --version | xargs echo gem)"
echo "💡 Reload your shell or run: source ~/.zshrc"
echo "💡 Install another version: RUBY_VERSION=3.3.5 bash dev/ruby.sh"
