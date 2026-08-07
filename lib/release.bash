# shellcheck shell=bash

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

resolve_release_version() {
    local event_name="${1:?event name required}"
    local dispatch_version="${2:-}"
    local ref_name="${3:-}"
    local tag semver without_build prerelease=false

    if [[ "$event_name" == workflow_dispatch ]]; then
        tag="v${dispatch_version}"
    else
        tag="$ref_name"
    fi
    [[ "$tag" == v* ]] || { echo "Invalid semantic version tag: $tag" >&2; return 2; }
    semver="${tag#v}"
    is_semver "$semver" || { echo "Invalid semantic version tag: $tag" >&2; return 2; }
    without_build="${semver%%+*}"
    [[ "$without_build" == *-* ]] && prerelease=true
    printf '%s|%s|%s\n' "$tag" "$semver" "$prerelease"
}
