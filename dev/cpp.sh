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

echo "🚀 Installing C/C++ toolchain..."

# dev/flutter.sh installs clang/cmake/ninja/pkg-config as Linux-desktop build
# deps; this script is for native work without pulling in Flutter, and adds
# the debuggers, formatter, and static analysis that Flutter doesn't need.
install_if_missing() {
    local cmd="$1"
    local pkg="$2"
    if command -v "$cmd" &>/dev/null; then
        echo "✅ $cmd already installed"
    else
        echo "📦 Installing $pkg..."
        sudo apt-get install -y "$pkg"
    fi
}

sudo apt-get update

# Compilers + core build tooling
install_if_missing gcc         build-essential
install_if_missing clang       clang
install_if_missing cmake       cmake
install_if_missing ninja       ninja-build
install_if_missing pkg-config  pkg-config
install_if_missing ccache      ccache

# Debuggers
install_if_missing gdb         gdb
install_if_missing lldb        lldb

# Formatting + static analysis
install_if_missing clang-format clang-format
install_if_missing clang-tidy   clang-tidy
install_if_missing cppcheck     cppcheck

# Profiling / memory checking
install_if_missing valgrind    valgrind

echo ""
echo "✅ C/C++ toolchain installed!"
echo "   gcc / clang    - compilers"
echo "   cmake / ninja  - build systems"
echo "   ccache         - compiler cache (speeds up rebuilds)"
echo "   gdb / lldb     - debuggers"
echo "   clang-format   - formatter"
echo "   clang-tidy     - linter"
echo "   cppcheck       - static analyzer"
echo "   valgrind       - memory error detector"
echo "💡 Enable ccache for a project: cmake -DCMAKE_CXX_COMPILER_LAUNCHER=ccache ..."
