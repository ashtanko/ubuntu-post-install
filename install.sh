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

is_semver() {
    local version="${1:-}"
    local without_build prerelease identifier
    local -a identifiers=()
    local pattern='^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?(\+[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?$'

    [[ "$version" =~ $pattern ]] || return 1
    without_build="${version%%+*}"
    [[ "$without_build" == *-* ]] || return 0
    prerelease="${without_build#*-}"
    IFS='.' read -r -a identifiers <<< "$prerelease"
    for identifier in "${identifiers[@]}"; do
        if [[ "$identifier" =~ ^[0-9]+$ ]] && [[ "$identifier" != 0 && "$identifier" == 0* ]]; then
            return 1
        fi
    done
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Deliberately avoids api.github.com: unauthenticated calls are rate-limited to
# 60/hour per IP, so a curl-to-bash install run from a shared IP (CI, corporate
# NAT, cloud VM) can start getting 403s. The /releases/latest redirect carries
# the same tag and isn't rate-limited that way — same approach as
# lib/github.bash's latest_github_tag, used by every other script in the repo.
resolve_latest_tag() {
    local url
    url=$(curl -fsSLI --retry 3 --retry-all-errors -o /dev/null \
        -w '%{url_effective}' "https://github.com/${REPO}/releases/latest") || return 1
    case "$url" in
        */releases/tag/*) printf '%s\n' "${url##*/releases/tag/}" ;;
        *) return 1 ;;
    esac
}

TAG="${VERSION:-}"
if [[ -z "$TAG" ]]; then
    info "Resolving latest release..."
    # `if !` (not a bare assignment) so a failed lookup falls through to the
    # error message below instead of triggering `set -e` silently.
    if ! TAG="$(resolve_latest_tag)"; then
        fail "could not resolve latest release tag for $REPO"
        exit 1
    fi
fi

# Accept v1.2.3 or 1.2.3
[[ "$TAG" != v* ]] && TAG="v$TAG"
SEMVER="${TAG#v}"
is_semver "$SEMVER" || {
    fail "invalid semantic version: $TAG"
    exit 2
}

TARBALL="ubuntu-post-install-${SEMVER}.tar.gz"
BASE_URL="${RELEASE_BASE_URL:-https://github.com/${REPO}/releases/download/${TAG}}"
BASE_URL="${BASE_URL%/}"

info "Installing ubuntu-post-install ${TAG}"
info "Source: ${BASE_URL}"

curl -fsSL --retry 3 --retry-all-errors -o "$TMP/$TARBALL"   "$BASE_URL/$TARBALL"
curl -fsSL --retry 3 --retry-all-errors -o "$TMP/SHA256SUMS" "$BASE_URL/SHA256SUMS"

mapfile -t TARBALL_CHECKSUMS < <(awk -v name="$TARBALL" '$2 == name { print $1 }' "$TMP/SHA256SUMS")
if [ "${#TARBALL_CHECKSUMS[@]}" -ne 1 ] \
    || [[ ! "${TARBALL_CHECKSUMS[0]}" =~ ^[0-9a-fA-F]{64}$ ]]; then
    fail "SHA256SUMS must contain exactly one valid checksum for $TARBALL"
    exit 1
fi
echo "${TARBALL_CHECKSUMS[0]}  $TMP/$TARBALL" | sha256sum --check --status
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
info "Configuration: ${UBUNTU_POST_INSTALL_CONFIG:-$HOME/.env-ubuntu-post-install}"

case ":$PATH:" in
    *":$BIN_DIR:"*) ;;
    *) warn "$BIN_DIR is not on your PATH — add it, or run $LINK directly" ;;
esac

cat <<EOF

  Next steps:
    1. (optional) cp $INSTALL_DIR/.env.example ${UBUNTU_POST_INSTALL_CONFIG:-$HOME/.env-ubuntu-post-install}
    2. ubuntu-post-install --version
    3. ubuntu-post-install            # launches the interactive menu

EOF
