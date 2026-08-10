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

echo "🚀 Installing PHP + Composer..."

PHP_VERSION="${PHP_VERSION:-8.3}"
BIN_DIR="/usr/local/bin"

# --- PHP (ondrej/php PPA — the de facto source for current PHP on Ubuntu;
# Ubuntu's own universe package lags upstream by one or more majors) ---
if command -v "php${PHP_VERSION}" &>/dev/null || { command -v php &>/dev/null && [[ "$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')" == "$PHP_VERSION" ]]; }; then
    echo "✅ PHP $PHP_VERSION already installed ($(php -v | head -1))"
else
    echo "📦 Adding ondrej/php PPA..."
    sudo apt-get update
    sudo apt-get install -y software-properties-common
    sudo add-apt-repository -y ppa:ondrej/php
    sudo apt-get update

    echo "📦 Installing php${PHP_VERSION} + common extensions..."
    sudo apt-get install -y \
        "php${PHP_VERSION}-cli" "php${PHP_VERSION}-common" "php${PHP_VERSION}-mbstring" \
        "php${PHP_VERSION}-xml" "php${PHP_VERSION}-curl" "php${PHP_VERSION}-zip" \
        "php${PHP_VERSION}-mysql" "php${PHP_VERSION}-sqlite3"
    sudo update-alternatives --set php "/usr/bin/php${PHP_VERSION}" 2>/dev/null || true
    echo "✅ PHP $PHP_VERSION installed ($(php -v | head -1))"
fi

# --- Composer (official installer, with its documented signature check —
# same "don't trust an unverified download" posture as the checksum
# verification used for lazygit/k9s/kind/kustomize elsewhere in this repo) ---
if command -v composer &>/dev/null; then
    echo "✅ Composer already installed ($(composer --version 2>/dev/null | head -1))"
else
    echo "📦 Ensuring php-cli + unzip are present..."
    sudo apt-get install -y unzip

    TMP=$(mktemp -d)
    trap 'rm -rf "$TMP"' EXIT

    echo "📥 Downloading Composer installer..."
    curl -fsSL --retry 3 --retry-all-errors -o "$TMP/composer-setup.php" https://getcomposer.org/installer

    echo "🔒 Verifying installer signature..."
    EXPECTED_SIG=$(curl -fsSL --retry 3 --retry-all-errors https://composer.github.io/installer.sig)
    ACTUAL_SIG=$(php -r "echo hash_file('sha384', '$TMP/composer-setup.php');")
    if [ "$EXPECTED_SIG" != "$ACTUAL_SIG" ]; then
        echo "❌ Composer installer signature mismatch — refusing to run it"
        exit 1
    fi
    echo "✅ Signature verified"

    php "$TMP/composer-setup.php" --quiet --install-dir="$TMP" --filename=composer
    sudo install -m 0755 "$TMP/composer" "$BIN_DIR/composer"
    echo "✅ Composer installed → $BIN_DIR/composer"
fi

echo ""
echo "✅ PHP toolchain ready!"
echo "   $(php -v | head -1)"
echo "   $(composer --version 2>/dev/null | head -1)"
echo "💡 Install another version: PHP_VERSION=8.2 bash dev/php.sh"
