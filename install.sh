#!/bin/bash
set -euo pipefail

# Re-exec under bash if invoked via `sh` (dash mishandles &>, [[ ]], etc.)
if [ -z "${BASH_VERSION:-}" ]; then
    exec /bin/bash "$0" "$@"
fi

REPO="${REPO:-ashtanko/ubuntu-post-install}"
PREFIX="${PREFIX:-$HOME/.local/share/ubuntu-post-install}"
BIN_DIR="${BIN_DIR:-$HOME/.local/bin}"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; RESET='\033[0m'
info()    { echo -e "${CYAN}  💡 $*${RESET}"; }
success() { echo -e "${GREEN}  ✅ $*${RESET}"; }
warn()    { echo -e "${YELLOW}  ⚠️  $*${RESET}"; }
fail()    { echo -e "${RED}  ❌ $*${RESET}" >&2; }

require() {
    command -v "$1" >/dev/null 2>&1 || { fail "missing required command: $1"; exit 1; }
}

require curl
require tar
require sha256sum

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

resolve_latest_tag() {
    local api="https://api.github.com/repos/${REPO}/releases/latest"
    local auth=()
    [[ -n "${GITHUB_TOKEN:-}" ]] && auth=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
    curl -fsSL "${auth[@]}" "$api" \
        | grep -m1 '"tag_name"' \
        | sed -E 's/.*"tag_name"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/'
}

TAG="${VERSION:-}"
if [[ -z "$TAG" ]]; then
    info "Resolving latest release..."
    TAG="$(resolve_latest_tag)"
    [[ -z "$TAG" ]] && { fail "could not resolve latest release tag for $REPO"; exit 1; }
fi

# Accept v1.2.3 or 1.2.3
[[ "$TAG" != v* ]] && TAG="v$TAG"
SEMVER="${TAG#v}"

TARBALL="ubuntu-post-install-${SEMVER}.tar.gz"
BASE_URL="https://github.com/${REPO}/releases/download/${TAG}"

info "Installing ubuntu-post-install ${TAG}"
info "Source: ${BASE_URL}"

curl -fsSL -o "$TMP/$TARBALL"   "$BASE_URL/$TARBALL"
curl -fsSL -o "$TMP/SHA256SUMS" "$BASE_URL/SHA256SUMS"

(cd "$TMP" && sha256sum -c --ignore-missing SHA256SUMS) >/dev/null
success "Checksum verified"

INSTALL_DIR="$PREFIX/$SEMVER"
mkdir -p "$INSTALL_DIR"
# Strip the top-level ubuntu-post-install-<version>/ directory from the tarball.
tar -xzf "$TMP/$TARBALL" -C "$INSTALL_DIR" --strip-components=1

LINK="$BIN_DIR/ubuntu-post-install"
mkdir -p "$BIN_DIR"

if [[ -e "$LINK" || -L "$LINK" ]]; then
    if [[ -L "$LINK" ]] && [[ "$(readlink -f "$LINK")" == "$PREFIX"/* ]]; then
        rm -f "$LINK"
    else
        fail "$LINK already exists and is not managed by this installer; refusing to overwrite"
        exit 1
    fi
fi
ln -s "$INSTALL_DIR/setup.sh" "$LINK"

success "Installed to $INSTALL_DIR"
success "Symlink: $LINK -> $INSTALL_DIR/setup.sh"

case ":$PATH:" in
    *":$BIN_DIR:"*) ;;
    *) warn "$BIN_DIR is not on your PATH — add it, or run $LINK directly" ;;
esac

cat <<EOF

  Next steps:
    1. (optional) cp $INSTALL_DIR/.env.example ~/.env-ubuntu-post-install
    2. ubuntu-post-install --version
    3. ubuntu-post-install            # launches the interactive menu

EOF
