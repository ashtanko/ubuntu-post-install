#!/bin/bash
set -euo pipefail

SEMVER="${1:?usage: tests/release-artifact.sh SEMVER [DIST_DIR]}"
DIST_DIR="${2:-dist}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/release.bash
source "$REPO_ROOT/lib/release.bash"
is_semver "$SEMVER" || {
    echo "❌ invalid semantic version: $SEMVER"
    exit 2
}

TARBALL="$DIST_DIR/ubuntu-post-install-$SEMVER.tar.gz"
[[ -f "$TARBALL" && -f "$DIST_DIR/install.sh" && -f "$DIST_DIR/SHA256SUMS" ]] || {
    echo "❌ release artifact set is incomplete in $DIST_DIR"
    exit 1
}
(cd "$DIST_DIR" && sha256sum -c SHA256SUMS)

ROOT="ubuntu-post-install-$SEMVER"
mapfile -t members < <(tar -tzf "$TARBALL")
[[ "${#members[@]}" -gt 0 ]] || { echo "❌ release tarball is empty"; exit 1; }
for member in "${members[@]}"; do
    [[ "$member" == "$ROOT" || "$member" == "$ROOT/"* ]] || { echo "❌ unexpected archive path: $member"; exit 1; }
    [[ "$member" != *'/../'* && "$member" != ../* && "$member" != /* ]] || { echo "❌ unsafe archive path: $member"; exit 1; }
    [[ "$member" != "$ROOT/.env" && "$member" != "$ROOT/.git/"* \
        && "$member" != "$ROOT/.omx/"* && "$member" != "$ROOT/dist/"* ]] || {
        echo "❌ forbidden release content: $member"; exit 1;
    }
done

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
tar -xzf "$TARBALL" -C "$TMP"
[[ -f "$TMP/$ROOT/lib/config.bash" ]] || { echo "❌ config helper missing from artifact"; exit 1; }
[[ -f "$TMP/$ROOT/config/catalog.txt" ]] || { echo "❌ installer catalog missing from artifact"; exit 1; }
[[ -x "$TMP/$ROOT/bin/ubuntu-post-install-tui-amd64" ]] || { echo "❌ amd64 TUI missing from artifact"; exit 1; }
[[ -x "$TMP/$ROOT/bin/ubuntu-post-install-tui-arm64" ]] || { echo "❌ arm64 TUI missing from artifact"; exit 1; }
[[ "$(bash "$TMP/$ROOT/setup.sh" --version)" == *"$SEMVER"* ]] || { echo "❌ embedded setup version mismatch"; exit 1; }
bash -n "$DIST_DIR/install.sh" "$TMP/$ROOT/setup.sh" "$TMP/$ROOT/lib/config.bash"

case "$(uname -m)" in
    x86_64|amd64) HOST_TUI="$TMP/$ROOT/bin/ubuntu-post-install-tui-amd64" ;;
    aarch64|arm64) HOST_TUI="$TMP/$ROOT/bin/ubuntu-post-install-tui-arm64" ;;
    *) HOST_TUI="" ;;
esac
if [ -n "$HOST_TUI" ]; then
    "$HOST_TUI" --root "$TMP/$ROOT" --catalog "$TMP/$ROOT/config/catalog.txt" \
        --marker-dir "$TMP/markers" --log-file "$TMP/setup.log" --check >/dev/null
fi

INSTALL_HOME="$TMP/install-home"
mkdir -p "$INSTALL_HOME"
HOME="$INSTALL_HOME" PREFIX="$INSTALL_HOME/prefix" BIN_DIR="$INSTALL_HOME/bin" \
    VERSION="$SEMVER" RELEASE_BASE_URL="file://$(realpath "$DIST_DIR")" \
    bash "$DIST_DIR/install.sh" >/dev/null
[[ -L "$INSTALL_HOME/bin/ubuntu-post-install" ]] || { echo "❌ remote installer did not create its managed link"; exit 1; }
[[ -f "$INSTALL_HOME/prefix/$SEMVER/lib/config.bash" ]] || { echo "❌ remote installer omitted the config helper"; exit 1; }
[[ -x "$INSTALL_HOME/prefix/$SEMVER/bin/ubuntu-post-install-tui-amd64" ]] \
    || { echo "❌ remote installer omitted the amd64 TUI"; exit 1; }
LAUNCHER="$INSTALL_HOME/bin/ubuntu-post-install"
[[ "$("$LAUNCHER" --version)" == *"$SEMVER"* ]] || { echo "❌ installed launcher version mismatch"; exit 1; }

# Exercise the symlinked interactive entry point and both stable-config and
# environment precedence without selecting any host-mutating installer.
SETUP_INPUT=$'\nn\nn\nn\nn\nn\nn\nn\nn\nn'
# HOME must expand when the installed launcher sources this fixture.
# shellcheck disable=SC2016
printf '%s\n' 'SETUP_LOG_FILE="$HOME/installed-user-config.log"' \
    > "$INSTALL_HOME/.env-ubuntu-post-install"
HOME="$INSTALL_HOME" TERM=xterm "$LAUNCHER" <<< "$SETUP_INPUT" >/dev/null
[[ -f "$INSTALL_HOME/installed-user-config.log" ]] || { echo "❌ installed launcher ignored stable user config"; exit 1; }
HOME="$INSTALL_HOME" TERM=xterm SETUP_LOG_FILE="$INSTALL_HOME/installed-environment.log" \
    "$LAUNCHER" <<< "$SETUP_INPUT" >/dev/null
[[ -f "$INSTALL_HOME/installed-environment.log" ]] || { echo "❌ installed launcher ignored environment precedence"; exit 1; }

BAD_DIST="$TMP/missing-tarball-checksum"
mkdir -p "$BAD_DIST"
cp "$TARBALL" "$DIST_DIR/install.sh" "$BAD_DIST/"
(cd "$BAD_DIST" && sha256sum install.sh > SHA256SUMS)
if HOME="$INSTALL_HOME" PREFIX="$INSTALL_HOME/rejected" BIN_DIR="$INSTALL_HOME/rejected-bin" \
    VERSION="$SEMVER" RELEASE_BASE_URL="file://$(realpath "$BAD_DIST")" \
    bash "$DIST_DIR/install.sh" >/dev/null 2>&1; then
    echo "❌ remote installer accepted checksums that omitted the tarball"
    exit 1
fi
if HOME="$INSTALL_HOME" PREFIX="$INSTALL_HOME/invalid-version" BIN_DIR="$INSTALL_HOME/invalid-bin" \
    VERSION='1.2.3-01' RELEASE_BASE_URL="file://$(realpath "$DIST_DIR")" \
    bash "$DIST_DIR/install.sh" >/dev/null 2>&1; then
    echo "❌ remote installer accepted invalid SemVer"
    exit 1
fi

echo "✅ release artifact $SEMVER verified (${#members[@]} archive entries)"
