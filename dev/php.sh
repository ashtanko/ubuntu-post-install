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

# A version the caller pinned is honoured exactly; a defaulted one may fall
# back to whatever the enabled repos actually carry (see below).
PHP_VERSION_PINNED="${PHP_VERSION:+yes}"
PHP_VERSION="${PHP_VERSION:-8.3}"
BIN_DIR="/usr/local/bin"
UBUNTU_CODENAME=$(. /etc/os-release && echo "${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}")

# `apt-cache policy` prints nothing for an unknown package and
# "Candidate: (none)" for one that exists but cannot be installed.
apt_has_candidate() {
    apt-cache policy "$1" 2>/dev/null | grep -q 'Candidate: [^(]'
}

available_php_versions() {
    apt-cache pkgnames php 2>/dev/null \
        | sed -n 's/^php\([0-9][0-9]*\.[0-9][0-9]*\)-cli$/\1/p' \
        | sort -uV
}

# The PPA only publishes for a subset of Ubuntu suites — nothing for plucky,
# questing, or resolute — and adding a suite it does not carry breaks every
# later `apt-get update` with a 404 on the missing Release file.
ppa_publishes_suite() {
    [ -n "$1" ] && curl -fsSL --retry 3 --retry-all-errors -o /dev/null \
        "https://ppa.launchpadcontent.net/ondrej/php/ubuntu/dists/$1/Release"
}

php_version_present() {
    command -v "php${PHP_VERSION}" &>/dev/null \
        || { command -v php &>/dev/null \
            && [[ "$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')" == "$PHP_VERSION" ]]; }
}

# --- PHP (ondrej/php PPA where it publishes — the de facto source for current
# PHP on Ubuntu; Ubuntu's own universe package lags upstream by one or more
# majors — otherwise the distro's own packages) ---
if php_version_present; then
    echo "✅ PHP $PHP_VERSION already installed ($(php -v | head -1))"
else
    sudo apt-get update
    sudo apt-get install -y software-properties-common curl ca-certificates

    if ppa_publishes_suite "$UBUNTU_CODENAME"; then
        echo "📦 Adding ondrej/php PPA..."
        sudo add-apt-repository -y ppa:ondrej/php
        sudo apt-get update
    else
        echo "⚠️  ondrej/php publishes nothing for Ubuntu ${UBUNTU_CODENAME:-unknown} — using the distro's own PHP packages"
    fi

    if ! apt_has_candidate "php${PHP_VERSION}-cli"; then
        AVAILABLE=$(available_php_versions | tr '\n' ' ')
        if [ -n "$PHP_VERSION_PINNED" ]; then
            echo "❌ php${PHP_VERSION} is not available on Ubuntu ${UBUNTU_CODENAME:-unknown}"
            echo "   Available PHP versions here: ${AVAILABLE:-none}"
            exit 1
        fi

        FALLBACK=$(available_php_versions | tail -1)
        if [ -z "$FALLBACK" ]; then
            echo "❌ No php*-cli package is available on Ubuntu ${UBUNTU_CODENAME:-unknown}"
            exit 1
        fi

        echo "⚠️  php${PHP_VERSION} is not available on Ubuntu ${UBUNTU_CODENAME:-unknown} — installing php${FALLBACK} instead"
        PHP_VERSION="$FALLBACK"
    fi

    # Re-checked with the resolved version so a re-run skips the install
    # instead of handing apt packages it has already installed.
    if php_version_present; then
        echo "✅ PHP $PHP_VERSION already installed ($(php -v | head -1))"
    else
        echo "📦 Installing php${PHP_VERSION} + common extensions..."
        sudo apt-get install -y \
            "php${PHP_VERSION}-cli" "php${PHP_VERSION}-common" "php${PHP_VERSION}-mbstring" \
            "php${PHP_VERSION}-xml" "php${PHP_VERSION}-curl" "php${PHP_VERSION}-zip" \
            "php${PHP_VERSION}-mysql" "php${PHP_VERSION}-sqlite3"
        sudo update-alternatives --set php "/usr/bin/php${PHP_VERSION}" 2>/dev/null || true
        echo "✅ PHP $PHP_VERSION installed ($(php -v | head -1))"
    fi
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
