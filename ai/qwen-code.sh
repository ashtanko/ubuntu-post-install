#!/bin/bash
set -euo pipefail

if [ -z "${BASH_VERSION:-}" ]; then
    exec /bin/bash "$0" "$@"
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_HELPER="$REPO_ROOT/lib/config.bash"
# shellcheck source=lib/config.bash
source "$CONFIG_HELPER" || { echo "❌ Missing config helper: $CONFIG_HELPER" >&2; exit 1; }
load_config "$REPO_ROOT"

echo "🚀 Installing Qwen Code..."

PROFILE_FILE="$HOME/.profile"

ensure_qwen_path() {
    local marker="# Qwen Code paths (added by qwen-code.sh)"
    # shellcheck disable=SC2016
    local path_line='for dir in "$HOME/.local/bin" "$HOME/.qwen/bin"; do [ -d "$dir" ] && case ":$PATH:" in *":$dir:"*) ;; *) PATH="$dir:$PATH";; esac; done; export PATH'
    if { [ -f "$PROFILE_FILE" ] && grep -qF "$marker" "$PROFILE_FILE"; } \
        || { [ -f "$PROFILE_FILE" ] && grep -Eq '^[^#]*PATH=.*(\.local/bin|\.qwen/bin)' "$PROFILE_FILE"; }; then
        return
    fi
    {
        echo ""
        echo "$marker"
        echo "$path_line"
    } >> "$PROFILE_FILE"
    echo "✅ Added Qwen Code directories to PATH in $PROFILE_FILE"
}

find_qwen() {
    if command -v qwen &>/dev/null; then
        command -v qwen
    elif [ -x "$HOME/.local/bin/qwen" ]; then
        printf '%s\n' "$HOME/.local/bin/qwen"
    elif [ -x "$HOME/.qwen/bin/qwen" ]; then
        printf '%s\n' "$HOME/.qwen/bin/qwen"
    else
        return 1
    fi
}

if QWEN_BIN=$(find_qwen); then
    ensure_qwen_path
    echo "✅ Qwen Code already installed ($("$QWEN_BIN" --version 2>/dev/null || echo 'version unknown'))"
    exit 0
fi

echo "📦 Downloading the official Qwen Code standalone installer..."
QWEN_INSTALLER=$(mktemp)
trap 'rm -f "$QWEN_INSTALLER"' EXIT
curl -fsSL --retry 3 --retry-all-errors \
    -o "$QWEN_INSTALLER" \
    https://qwen-code-assets.oss-cn-hangzhou.aliyuncs.com/installation/install-qwen-standalone.sh
PATH="$HOME/.local/bin:$HOME/.qwen/bin:$PATH" bash "$QWEN_INSTALLER"
rm -f "$QWEN_INSTALLER"
trap - EXIT

if ! QWEN_BIN=$(find_qwen); then
    echo "❌ Qwen Code installation failed or 'qwen' was not found" >&2
    exit 1
fi

ensure_qwen_path
echo "✅ Qwen Code installed successfully ($("$QWEN_BIN" --version 2>/dev/null || echo 'version unknown'))"
echo "💡 Run 'qwen', then use /auth to configure a provider"
