#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER="$REPO_ROOT/lib/config.bash"
[[ -f "$HELPER" ]] || { echo "❌ missing config helper: $HELPER"; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/repo" "$TMP/home"

printf '%s\n' 'CONFIG_VALUE=user' 'USER_ONLY=present' > "$TMP/home/.env-ubuntu-post-install"
printf '%s\n' 'CONFIG_VALUE=repo' 'export CONFIG_SECRET=not-for-children' > "$TMP/repo/.env"

HOME="$TMP/home" CONFIG_VALUE=environment REPO_UNDER_TEST="$TMP/repo" HELPER_UNDER_TEST="$HELPER" bash -c '
    set -euo pipefail
    source "$HELPER_UNDER_TEST"
    load_config "$REPO_UNDER_TEST"
    [[ "$CONFIG_VALUE" == environment ]]
    [[ "$USER_ONLY" == present ]]
    [[ "$CONFIG_SECRET" == not-for-children ]]
    [[ -z "$(env | grep "^CONFIG_SECRET=" || true)" ]]
'

HOME="$TMP/home" REPO_UNDER_TEST="$TMP/repo" HELPER_UNDER_TEST="$HELPER" bash -c '
    set -euo pipefail
    source "$HELPER_UNDER_TEST"
    load_config "$REPO_UNDER_TEST"
    [[ "$CONFIG_VALUE" == repo ]]
'

mkdir -p "$TMP/empty"
HOME="$TMP/empty" HELPER_UNDER_TEST="$HELPER" bash -c '
    set -euo pipefail
    source "$HELPER_UNDER_TEST"
    load_config "$HOME/missing-repo"
'

# Exercise the real setup entry point so the shared loader cannot be added without
# actually wiring its callers. Ten blank answers skip the initial prompt and all
# nine installation categories without touching the host.
mkdir -p "$TMP/setup-home"
# HOME must expand when setup sources the fixture.
# shellcheck disable=SC2016
printf '%s\n' 'SETUP_LOG_FILE="$HOME/from-user-config.log"' \
    > "$TMP/setup-home/.env-ubuntu-post-install"
SETUP_INPUT=$'\nn\nn\nn\nn\nn\nn\nn\nn\nn'
HOME="$TMP/setup-home" TERM=xterm bash "$REPO_ROOT/setup.sh" \
    <<< "$SETUP_INPUT" >/dev/null
[[ -f "$TMP/setup-home/from-user-config.log" ]] || {
    echo "❌ setup.sh did not load the stable user config path"
    exit 1
}

HOME="$TMP/setup-home" TERM=xterm SETUP_LOG_FILE="$TMP/setup-home/from-environment.log" \
    bash "$REPO_ROOT/setup.sh" <<< "$SETUP_INPUT" >/dev/null
[[ -f "$TMP/setup-home/from-environment.log" ]] || {
    echo "❌ setup.sh did not preserve the environment override"
    exit 1
}

echo "✅ config precedence, caller integration, and export isolation checks passed"
