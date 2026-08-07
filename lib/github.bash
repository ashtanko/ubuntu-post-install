# shellcheck shell=bash

# Resolve the newest release tag of a GitHub repository.
#
# Deliberately avoids api.github.com: unauthenticated API calls are rate-limited
# to 60/hour per IP, and CI runners share egress addresses, so the API starts
# answering 403 partway through a run. The /releases/latest redirect carries the
# same information and is not rate-limited that way.
latest_github_tag() {
    local repo="${1:?latest_github_tag requires a <owner>/<repo>}" url
    url=$(curl -fsSLI --retry 3 --retry-all-errors -o /dev/null \
        -w '%{url_effective}' "https://github.com/${repo}/releases/latest") || {
        echo "❌ Could not reach GitHub to resolve the latest $repo release" >&2
        return 1
    }
    case "$url" in
        */releases/tag/*) printf '%s\n' "${url##*/releases/tag/}" ;;
        *)
            echo "❌ Unexpected release URL for $repo: $url" >&2
            return 1
            ;;
    esac
}
