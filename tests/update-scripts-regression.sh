#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UPDATES_DIR="$REPO_ROOT/updates"
UPDATE_CATALOG="$UPDATES_DIR/catalog.txt"
SKIPPED_CATALOG="$UPDATES_DIR/skipped.txt"

mapfile -t EXPECTED_UPDATERS < <(
    awk -F'|' '!/^#/ && NF { print $1 }' "$UPDATE_CATALOG" | LC_ALL=C sort
)
mapfile -t INDIVIDUAL_UPDATERS < <(
    printf '%s\n' "${EXPECTED_UPDATERS[@]}" | grep -vx 'update-all.sh'
)

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/home" "$TMP/minimal-bin"

fail() {
    echo "❌ $*" >&2
    exit 1
}

assert_log_line() {
    local expected="$1"
    local log_file="$2"
    grep -Fqx -- "$expected" "$log_file" \
        || fail "expected '$expected' in $log_file"
}

declare -A CATALOG_UPDATERS=()
declare -A MAPPED_INSTALLERS=()
while IFS='|' read -r updater installers method extra; do
    [[ -z "$updater" || "$updater" == \#* ]] && continue
    [[ -n "$installers" && -n "$method" && -z "$extra" ]] \
        || fail "invalid update catalog row for $updater"
    [[ -z "${CATALOG_UPDATERS[$updater]:-}" ]] \
        || fail "duplicate updater in updates/catalog.txt: $updater"
    CATALOG_UPDATERS["$updater"]=1
    IFS=',' read -ra installer_paths <<<"$installers"
    for installer in "${installer_paths[@]}"; do
        [[ -f "$REPO_ROOT/$installer" ]] \
            || fail "catalog installer mapping does not exist: $updater -> $installer"
        MAPPED_INSTALLERS["$installer"]=1
    done
done <"$UPDATE_CATALOG"

# Every selectable installer must have either an updater mapping or a precise
# audited skip reason. This makes omissions deliberate and reviewable.
declare -A CONFIG_INSTALLERS=()
while IFS='|' read -r category category_label item_label installer extra; do
    [[ -z "$category" || "$category" == \#* ]] && continue
    [[ -n "$category_label" && -n "$item_label" && -n "$installer" && -z "$extra" ]] \
        || fail "invalid config catalog row for $installer"
    [[ -z "${CONFIG_INSTALLERS[$installer]:-}" ]] \
        || fail "duplicate installer in config/catalog.txt: $installer"
    CONFIG_INSTALLERS["$installer"]=1
done <"$REPO_ROOT/config/catalog.txt"

declare -A SKIPPED_INSTALLERS=()
while IFS='|' read -r installer reason extra; do
    [[ -z "$installer" || "$installer" == \#* ]] && continue
    [[ -n "$reason" && -z "$extra" ]] \
        || fail "invalid skipped updater row for $installer"
    [[ -n "${CONFIG_INSTALLERS[$installer]:-}" ]] \
        || fail "updates/skipped.txt references a non-catalog installer: $installer"
    [[ -z "${MAPPED_INSTALLERS[$installer]:-}" ]] \
        || fail "installer is both mapped and skipped: $installer"
    [[ -z "${SKIPPED_INSTALLERS[$installer]:-}" ]] \
        || fail "duplicate installer in updates/skipped.txt: $installer"
    SKIPPED_INSTALLERS["$installer"]=1
done <"$SKIPPED_CATALOG"

for installer in "${!CONFIG_INSTALLERS[@]}"; do
    if [[ -z "${MAPPED_INSTALLERS[$installer]:-}" \
        && -z "${SKIPPED_INSTALLERS[$installer]:-}" ]]; then
        fail "catalog installer has neither updater nor skip reason: $installer"
    fi
done

mapfile -t ACTUAL_UPDATERS < <(
    find "$UPDATES_DIR" -maxdepth 1 -type f -name 'update-*.sh' -printf '%f\n' | LC_ALL=C sort
)
[[ "${EXPECTED_UPDATERS[*]}" == "${ACTUAL_UPDATERS[*]}" ]] \
    || fail "updates/catalog.txt does not match the updater scripts on disk"

# The updater scripts need dirname to locate the repository before they can
# decide that their managed tool is absent. Nothing else is exposed, ensuring
# the skip tests cannot accidentally discover or mutate host-installed tools.
ln -s "$(command -v dirname)" "$TMP/minimal-bin/dirname"

for updater in "${EXPECTED_UPDATERS[@]}"; do
    script="$UPDATES_DIR/$updater"
    [[ -f "$script" ]] || fail "missing updater: updates/$updater"
    bash -n "$script" || fail "updater does not parse: updates/$updater"
done

for updater in "${INDIVIDUAL_UPDATERS[@]}"; do
    output="$TMP/${updater%.sh}.skip.log"
    if ! /usr/bin/env -i HOME="$TMP/home" PATH="$TMP/minimal-bin" \
        GO_INSTALL_DIR="$TMP/home/missing-go" \
        /bin/bash "$UPDATES_DIR/$updater" >"$output" 2>&1; then
        fail "updates/$updater did not skip successfully when its tool was absent"
    fi
    grep -Eqi 'skip|not installed' "$output" \
        || fail "updates/$updater did not explain why it skipped"
done

make_logging_tool() {
    local name="$1"
    local tool_dir="$2"
    mkdir -p "$tool_dir"
    sed "s/@TOOL@/$name/g" >"$tool_dir/$name" <<'STUB'
#!/bin/bash
printf '%s %s\n' '@TOOL@' "$*" >>"$UPDATE_TEST_LOG"
if [[ "${1:-}" == "--version" ]]; then
    echo '@TOOL@ test-version'
fi
STUB
    chmod +x "$tool_dir/$name"
}

run_mocked_tool_update() {
    local updater="$1"
    local tool="$2"
    local expected_invocation="$3"
    local managed_dir="${4:-}"
    local case_dir="$TMP/mock-$tool"
    local log_file="$case_dir/invocations.log"
    local tool_dir="$case_dir/bin"

    mkdir -p "$case_dir/home" "$case_dir/bin"
    ln -s "$(command -v dirname)" "$case_dir/bin/dirname"
    if [ -n "$managed_dir" ]; then
        tool_dir="$case_dir/home/$managed_dir"
    fi
    make_logging_tool "$tool" "$tool_dir"
    : >"$log_file"

    /usr/bin/env -i HOME="$case_dir/home" PATH="$case_dir/bin" UPDATE_TEST_LOG="$log_file" \
        /bin/bash "$UPDATES_DIR/$updater" >"$case_dir/output.log" 2>&1 \
        || fail "updates/$updater failed against the isolated $tool stub"
    assert_log_line "$expected_invocation" "$log_file"
}

# These tools provide their own updater command. Capture the exact invocation
# without allowing the real CLI, network, or filesystem updater to run.
run_mocked_tool_update update-deno.sh deno 'deno upgrade --quiet' '.deno/bin'
run_mocked_tool_update update-bun.sh bun 'bun upgrade' '.bun/bin'
run_mocked_tool_update update-rust.sh rustup 'rustup update' '.cargo/bin'
run_mocked_tool_update update-flutter.sh flutter 'flutter upgrade' 'development/flutter/bin'
run_mocked_tool_update update-aider.sh aider 'aider --upgrade' '.local/bin'
run_mocked_tool_update update-goose.sh goose 'goose update' '.local/bin'
run_mocked_tool_update update-github-copilot.sh copilot 'copilot update' '.local/bin'
run_mocked_tool_update update-cursor-agent.sh cursor-agent 'cursor-agent update' '.local/bin'
run_mocked_tool_update update-huggingface-cli.sh hf 'hf update' '.local/bin'
run_mocked_tool_update update-chezmoi.sh chezmoi 'chezmoi upgrade' '.local/bin'
run_mocked_tool_update update-atuin.sh atuin 'atuin update' '.atuin/bin'
run_mocked_tool_update update-codex.sh codex 'codex update' '.local/bin'
run_mocked_tool_update update-opencode.sh opencode 'opencode upgrade --method curl' '.opencode/bin'

# A repo-configured custom OpenCode directory must reach the child updater even
# though load_config intentionally does not export config-only values globally.
opencode_config_case="$TMP/mock-opencode-config"
opencode_config_repo="$opencode_config_case/repo"
opencode_custom_dir="$opencode_config_case/home/custom-opencode"
mkdir -p "$opencode_config_repo/updates" "$opencode_config_repo/lib" \
    "$opencode_custom_dir/bin" "$opencode_config_case/bin"
cp "$UPDATES_DIR/update-opencode.sh" "$opencode_config_repo/updates/"
cp "$REPO_ROOT/lib/config.bash" "$opencode_config_repo/lib/"
printf 'OPENCODE_INSTALL_DIR="%s"\n' "$opencode_custom_dir" >"$opencode_config_repo/.env"
ln -s "$(command -v dirname)" "$opencode_config_case/bin/dirname"
cat >"$opencode_custom_dir/bin/opencode" <<'OPENCODE_STUB'
#!/bin/bash
printf 'opencode %s\n' "$*" >>"$UPDATE_TEST_LOG"
printf 'opencode-install-dir=%s\n' "${OPENCODE_INSTALL_DIR:-unset}" >>"$UPDATE_TEST_LOG"
if [[ "${1:-}" == '--version' ]]; then
    echo 'opencode test-version'
fi
OPENCODE_STUB
chmod +x "$opencode_custom_dir/bin/opencode"
: >"$opencode_config_case/invocations.log"
/usr/bin/env -i HOME="$opencode_config_case/home" PATH="$opencode_config_case/bin" \
    UPDATE_TEST_LOG="$opencode_config_case/invocations.log" \
    /bin/bash "$opencode_config_repo/updates/update-opencode.sh" \
    >"$opencode_config_case/output.log" 2>&1 \
    || fail "update-opencode failed for a config-sourced custom installation path"
assert_log_line 'opencode upgrade --method curl' "$opencode_config_case/invocations.log"
assert_log_line "opencode-install-dir=$opencode_custom_dir" \
    "$opencode_config_case/invocations.log"

# Gemini must update only the executable owned by npm's active global prefix.
gemini_case="$TMP/mock-gemini-npm"
gemini_prefix="$gemini_case/home/.npm-global"
gemini_root="$gemini_prefix/lib/node_modules"
mkdir -p "$gemini_prefix/bin" "$gemini_root/@google/gemini-cli" "$gemini_case/bin"
for command_name in dirname readlink; do
    ln -s "$(command -v "$command_name")" "$gemini_case/bin/$command_name"
done
make_logging_tool gemini "$gemini_prefix/bin"
cat >"$gemini_case/bin/npm" <<NPM_STUB
#!/bin/bash
printf 'npm %s\n' "\$*" >>"\$UPDATE_TEST_LOG"
case "\$*" in
    'config get prefix') printf '%s\n' '$gemini_prefix' ;;
    'root -g') printf '%s\n' '$gemini_root' ;;
esac
NPM_STUB
chmod +x "$gemini_case/bin/npm"
: >"$gemini_case/invocations.log"
/usr/bin/env -i HOME="$gemini_case/home" PATH="$gemini_prefix/bin:$gemini_case/bin" \
    UPDATE_TEST_LOG="$gemini_case/invocations.log" \
    /bin/bash "$UPDATES_DIR/update-gemini.sh" >"$gemini_case/output.log" 2>&1 \
    || fail "updates/update-gemini.sh failed against the owned npm fixture"
assert_log_line 'npm install -g @google/gemini-cli@latest' "$gemini_case/invocations.log"

# MCP Inspector follows the same npm provenance rule and respects its package's
# scoped global directory.
inspector_case="$TMP/mock-mcp-inspector-npm"
inspector_prefix="$inspector_case/home/.npm-global"
inspector_root="$inspector_prefix/lib/node_modules"
mkdir -p "$inspector_prefix/bin" \
    "$inspector_root/@modelcontextprotocol/inspector" "$inspector_case/bin"
for command_name in dirname readlink; do
    ln -s "$(command -v "$command_name")" "$inspector_case/bin/$command_name"
done
make_logging_tool mcp-inspector "$inspector_prefix/bin"
cat >"$inspector_case/bin/npm" <<NPM_STUB
#!/bin/bash
printf 'npm %s\n' "\$*" >>"\$UPDATE_TEST_LOG"
case "\$*" in
    'config get prefix') printf '%s\n' '$inspector_prefix' ;;
    'root -g') printf '%s\n' '$inspector_root' ;;
esac
NPM_STUB
chmod +x "$inspector_case/bin/npm"
: >"$inspector_case/invocations.log"
/usr/bin/env -i HOME="$inspector_case/home" \
    PATH="$inspector_prefix/bin:$inspector_case/bin" \
    UPDATE_TEST_LOG="$inspector_case/invocations.log" \
    /bin/bash "$UPDATES_DIR/update-mcp-inspector.sh" \
    >"$inspector_case/output.log" 2>&1 \
    || fail "updates/update-mcp-inspector.sh failed against the owned npm fixture"
assert_log_line 'npm install -g @modelcontextprotocol/inspector@latest' \
    "$inspector_case/invocations.log"

# Cline's CLI updater is safe only when the active binary resolves inside the
# active npm global package directory.
cline_case="$TMP/mock-cline-npm"
cline_root="$cline_case/home/.npm-global/lib/node_modules"
mkdir -p "$cline_root/cline/bin" "$cline_case/bin"
for command_name in dirname readlink head; do
    ln -s "$(command -v "$command_name")" "$cline_case/bin/$command_name"
done
make_logging_tool cline "$cline_root/cline/bin"
ln -s "$cline_root/cline/bin/cline" "$cline_case/bin/cline"
cat >"$cline_case/bin/npm" <<NPM_STUB
#!/bin/bash
[[ "\$*" == 'root -g' ]] && printf '%s\n' '$cline_root'
NPM_STUB
chmod +x "$cline_case/bin/npm"
: >"$cline_case/invocations.log"
/usr/bin/env -i HOME="$cline_case/home" PATH="$cline_case/bin" \
    UPDATE_TEST_LOG="$cline_case/invocations.log" \
    /bin/bash "$UPDATES_DIR/update-cline.sh" >"$cline_case/output.log" 2>&1 \
    || fail "updates/update-cline.sh failed against the owned npm fixture"
assert_log_line 'cline update' "$cline_case/invocations.log"

# Update only the repository's named pipx tools, including LiteLLM's pinned
# compatibility dependencies. An unrelated package must remain untouched.
pipx_case="$TMP/mock-pipx"
mkdir -p "$pipx_case/home" "$pipx_case/bin"
for command_name in dirname awk; do
    ln -s "$(command -v "$command_name")" "$pipx_case/bin/$command_name"
done
cat >"$pipx_case/bin/pipx" <<'PIPX_STUB'
#!/bin/bash
printf 'pipx %s\n' "$*" >>"$UPDATE_TEST_LOG"
if [[ "$*" == 'list --short' ]]; then
    printf '%s\n' 'poetry 2.0' 'podman-compose 1.0' 'llm 1.0' 'litellm 1.0' 'unrelated 9.0'
fi
PIPX_STUB
chmod +x "$pipx_case/bin/pipx"
: >"$pipx_case/invocations.log"
/usr/bin/env -i HOME="$pipx_case/home" PATH="$pipx_case/bin" \
    UPDATE_TEST_LOG="$pipx_case/invocations.log" \
    /bin/bash "$UPDATES_DIR/update-pipx-tools.sh" >"$pipx_case/output.log" 2>&1 \
    || fail "updates/update-pipx-tools.sh failed against the pipx fixture"
assert_log_line 'pipx upgrade poetry' "$pipx_case/invocations.log"
assert_log_line 'pipx upgrade podman-compose' "$pipx_case/invocations.log"
assert_log_line 'pipx upgrade llm' "$pipx_case/invocations.log"
assert_log_line 'pipx upgrade litellm' "$pipx_case/invocations.log"
assert_log_line 'pipx runpip litellm install --upgrade fastapi>=0.136.3,<1.0 starlette>=1.0.1,<2.0' \
    "$pipx_case/invocations.log"
if grep -Fq 'pipx upgrade unrelated' "$pipx_case/invocations.log"; then
    fail "update-pipx-tools upgraded a package outside the managed allowlist"
fi

# Fixed-version configuration must prevent each latest-release updater from
# changing the pinned tool, including mixed pinned/unpinned pipx installs.
for pinned_spec in \
    "codex|CODEX_RELEASE|v1.2.3|$TMP/mock-codex|codex update" \
    "github-copilot|COPILOT_VERSION|1.2.3|$TMP/mock-copilot|copilot update" \
    "cline|CLINE_VERSION|1.2.3|$cline_case|cline update" \
    "mcp-inspector|MCP_INSPECTOR_VERSION|1.2.3|$inspector_case|npm install -g @modelcontextprotocol/inspector@latest"; do
    IFS='|' read -r pinned_tool pin_name pin_value pin_case forbidden <<<"$pinned_spec"
    : >"$pin_case/invocations.log"
    /usr/bin/env -i HOME="$pin_case/home" PATH="$pin_case/bin:$pin_case/home/.local/bin" \
        "$pin_name=$pin_value" UPDATE_TEST_LOG="$pin_case/invocations.log" \
        /bin/bash "$UPDATES_DIR/update-${pinned_tool}.sh" \
        >"$pin_case/pinned-output.log" 2>&1 \
        || fail "update-$pinned_tool failed while honoring $pin_name"
    if grep -Fq "$forbidden" "$pin_case/invocations.log"; then
        fail "update-$pinned_tool ignored $pin_name"
    fi
    grep -Fqi 'pinned' "$pin_case/pinned-output.log" \
        || fail "update-$pinned_tool did not explain its pinned skip"
done

: >"$pipx_case/invocations.log"
/usr/bin/env -i HOME="$pipx_case/home" PATH="$pipx_case/bin" \
    LLM_VERSION=1.2.3 LITELLM_VERSION=1.2.3 \
    UPDATE_TEST_LOG="$pipx_case/invocations.log" \
    /bin/bash "$UPDATES_DIR/update-pipx-tools.sh" >"$pipx_case/pinned-output.log" 2>&1 \
    || fail "update-pipx-tools failed while honoring LLM/LiteLLM pins"
if grep -Eq '^pipx upgrade (llm|litellm)$' "$pipx_case/invocations.log"; then
    fail "update-pipx-tools upgraded a pinned LLM or LiteLLM installation"
fi
assert_log_line 'pipx upgrade poetry' "$pipx_case/invocations.log"
assert_log_line 'pipx upgrade podman-compose' "$pipx_case/invocations.log"
grep -Fq 'llm=1.2.3' "$pipx_case/pinned-output.log" \
    || fail "update-pipx-tools did not report the pinned LLM version"
grep -Fq 'litellm=1.2.3' "$pipx_case/pinned-output.log" \
    || fail "update-pipx-tools did not report the pinned LiteLLM version"

# Go stages and validates a verified SDK before swapping the managed directory.
# Exercise the full user-local swap with an offline release feed and archive.
go_case="$TMP/mock-go-release"
go_install="$go_case/home/sdk/go"
mkdir -p "$go_install/bin" "$go_case/payload/go/bin" "$go_case/bin"
cat >"$go_install/bin/go" <<'GO_OLD'
#!/bin/bash
echo 'go version go1.20.0 linux/amd64'
GO_OLD
cat >"$go_case/payload/go/bin/go" <<'GO_NEW'
#!/bin/bash
echo 'go version go1.99.0 linux/amd64'
GO_NEW
chmod +x "$go_install/bin/go" "$go_case/payload/go/bin/go"
tar -C "$go_case/payload" -czf "$go_case/go1.99.0.linux-amd64.tar.gz" go
go_sha=$(sha256sum "$go_case/go1.99.0.linux-amd64.tar.gz" | awk '{print $1}')
cat >"$go_case/releases.json" <<GO_JSON
[
  {
    "version": "go1.99.0",
    "stable": true,
    "files": [
      {
        "filename": "go1.99.0.linux-amd64.tar.gz",
        "sha256": "$go_sha"
      }
    ]
  }
]
GO_JSON
for command_name in dirname realpath python3 tar gzip sha256sum mktemp rm awk mkdir mv; do
    ln -s "$(command -v "$command_name")" "$go_case/bin/$command_name"
done
ln -s /usr/bin/test "$go_case/bin/test"
cat >"$go_case/bin/dpkg" <<'DPKG_STUB'
#!/bin/bash
[[ "$*" == '--print-architecture' ]] && echo amd64
DPKG_STUB
cat >"$go_case/bin/curl" <<'CURL_STUB'
#!/bin/bash
output=''
url=''
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        -o) output="$2"; shift 2 ;;
        http*) url="$1"; shift ;;
        *) shift ;;
    esac
done
case "$url" in
    *'?mode=json') /bin/cp "$GO_TEST_METADATA" "$output" ;;
    *.tar.gz) /bin/cp "$GO_TEST_ARCHIVE" "$output" ;;
    *) exit 64 ;;
esac
CURL_STUB
chmod +x "$go_case/bin/dpkg" "$go_case/bin/curl"
/usr/bin/env -i HOME="$go_case/home" PATH="$go_case/bin" \
    GO_INSTALL_DIR="$go_install" \
    GO_TEST_METADATA="$go_case/releases.json" \
    GO_TEST_ARCHIVE="$go_case/go1.99.0.linux-amd64.tar.gz" \
    /bin/bash "$UPDATES_DIR/update-go.sh" >"$go_case/output.log" 2>&1 \
    || { cat "$go_case/output.log" >&2; fail "updates/update-go.sh failed its offline verified swap fixture"; }
if ! "$go_install/bin/go" version | grep -Fqx 'go version go1.99.0 linux/amd64'; then
    fail "update-go did not activate the staged SDK"
fi
if find "$go_case/home/sdk" -maxdepth 1 -name '.go-update-*' | grep -q .; then
    fail "update-go left a staging or backup directory after a successful swap"
fi
/usr/bin/env -i HOME="$go_case/home" PATH="$go_case/bin" \
    GO_INSTALL_DIR="$go_install" GO_VERSION=go1.99.0 \
    /bin/bash "$UPDATES_DIR/update-go.sh" >"$go_case/pinned-output.log" 2>&1 \
    || fail "update-go failed while honoring GO_VERSION"
grep -Fqi 'pinned' "$go_case/pinned-output.log" \
    || fail "update-go did not report its GO_VERSION skip"

# A candidate that works only in the extraction stage must trigger post-swap
# rollback, leaving the previously active SDK intact.
mkdir -p "$go_case/rollback-payload/go/bin"
cat >"$go_case/rollback-payload/go/bin/go" <<'GO_BAD_AFTER_SWAP'
#!/bin/bash
case "$0" in
    */extract/go/bin/go) echo 'go version go1.100.0 linux/amd64' ;;
    *) exit 42 ;;
esac
GO_BAD_AFTER_SWAP
chmod +x "$go_case/rollback-payload/go/bin/go"
tar -C "$go_case/rollback-payload" -czf "$go_case/go1.100.0.linux-amd64.tar.gz" go
go_rollback_sha=$(sha256sum "$go_case/go1.100.0.linux-amd64.tar.gz" | awk '{print $1}')
cat >"$go_case/rollback-releases.json" <<GO_ROLLBACK_JSON
[
  {
    "version": "go1.100.0",
    "stable": true,
    "files": [
      {
        "filename": "go1.100.0.linux-amd64.tar.gz",
        "sha256": "$go_rollback_sha"
      }
    ]
  }
]
GO_ROLLBACK_JSON
if /usr/bin/env -i HOME="$go_case/home" PATH="$go_case/bin" \
    GO_INSTALL_DIR="$go_install" \
    GO_TEST_METADATA="$go_case/rollback-releases.json" \
    GO_TEST_ARCHIVE="$go_case/go1.100.0.linux-amd64.tar.gz" \
    /bin/bash "$UPDATES_DIR/update-go.sh" >"$go_case/rollback-output.log" 2>&1; then
    fail "update-go accepted an SDK that failed after activation"
fi
if ! "$go_install/bin/go" version | grep -Fqx 'go version go1.99.0 linux/amd64'; then
    fail "update-go did not restore the previous SDK after post-swap validation failed"
fi
if find "$go_case/home/sdk" -maxdepth 1 -name '.go-update-*' | grep -q .; then
    fail "update-go left rollback artifacts after restoring the previous SDK"
fi

nvim_pin_case="$TMP/mock-nvim-pin"
nvim_pin_install="$nvim_pin_case/home/.local/share/nvim-stable"
mkdir -p "$nvim_pin_install/bin" "$nvim_pin_case/home/.local/bin" "$nvim_pin_case/bin"
make_logging_tool nvim "$nvim_pin_install/bin"
ln -s "$nvim_pin_install/bin/nvim" "$nvim_pin_case/home/.local/bin/nvim"
for command_name in dirname readlink; do
    ln -s "$(command -v "$command_name")" "$nvim_pin_case/bin/$command_name"
done
: >"$nvim_pin_case/invocations.log"
/usr/bin/env -i HOME="$nvim_pin_case/home" PATH="$nvim_pin_case/bin" \
    NVIM_VERSION=v0.11.4 UPDATE_TEST_LOG="$nvim_pin_case/invocations.log" \
    /bin/bash "$UPDATES_DIR/update-nvim.sh" >"$nvim_pin_case/output.log" 2>&1 \
    || fail "update-nvim failed while honoring NVIM_VERSION"
grep -Fqi 'pinned' "$nvim_pin_case/output.log" \
    || fail "update-nvim did not report its NVIM_VERSION skip"
if [[ -s "$nvim_pin_case/invocations.log" ]]; then
    fail "update-nvim invoked the managed binary despite NVIM_VERSION"
fi

# Mistral Vibe is an explicitly named uv tool rather than a broad tool upgrade.
mistral_case="$TMP/mock-mistral-vibe"
mkdir -p "$mistral_case/home/.local/share/uv/tools/mistral-vibe" \
    "$mistral_case/home/.local/bin" "$mistral_case/bin"
ln -s "$(command -v dirname)" "$mistral_case/bin/dirname"
make_logging_tool vibe "$mistral_case/home/.local/bin"
make_logging_tool uv "$mistral_case/bin"
: >"$mistral_case/invocations.log"
/usr/bin/env -i HOME="$mistral_case/home" PATH="$mistral_case/bin" \
    UPDATE_TEST_LOG="$mistral_case/invocations.log" \
    /bin/bash "$UPDATES_DIR/update-mistral-vibe.sh" >"$mistral_case/output.log" 2>&1 \
    || fail "updates/update-mistral-vibe.sh failed against the uv fixture"
assert_log_line 'uv tool upgrade mistral-vibe' "$mistral_case/invocations.log"

# Android Studio's updater must target only its snap, not refresh every snap.
android_case="$TMP/mock-android-studio"
mkdir -p "$android_case/home" "$android_case/bin"
for command_name in dirname awk; do
    ln -s "$(command -v "$command_name")" "$android_case/bin/$command_name"
done
cat >"$android_case/bin/snap" <<'SNAP_STUB'
#!/bin/bash
printf 'snap %s\n' "$*" >>"$UPDATE_TEST_LOG"
if [[ "$*" == 'list android-studio' ]]; then
    printf '%s\n' 'Name Version Rev Tracking Publisher Notes' 'android-studio 2026.1 1 latest/stable google classic'
fi
SNAP_STUB
cat >"$android_case/bin/sudo" <<'SUDO_STUB'
#!/bin/bash
printf 'sudo %s\n' "$*" >>"$UPDATE_TEST_LOG"
SUDO_STUB
chmod +x "$android_case/bin/snap" "$android_case/bin/sudo"
: >"$android_case/invocations.log"
/usr/bin/env -i HOME="$android_case/home" PATH="$android_case/bin" \
    UPDATE_TEST_LOG="$android_case/invocations.log" \
    /bin/bash "$UPDATES_DIR/update-android-studio.sh" >"$android_case/output.log" 2>&1 \
    || fail "updates/update-android-studio.sh failed against the snap fixture"
assert_log_line 'sudo snap refresh android-studio' "$android_case/invocations.log"

# Fisher uses Fish's command mode and updates Fisher plus installed plugins.
fisher_case="$TMP/mock-fisher"
mkdir -p "$fisher_case/home" "$fisher_case/bin"
for command_name in dirname head; do
    ln -s "$(command -v "$command_name")" "$fisher_case/bin/$command_name"
done
make_logging_tool fish "$fisher_case/bin"
: >"$fisher_case/invocations.log"
/usr/bin/env -i HOME="$fisher_case/home" PATH="$fisher_case/bin" \
    UPDATE_TEST_LOG="$fisher_case/invocations.log" \
    /bin/bash "$UPDATES_DIR/update-fisher.sh" >"$fisher_case/output.log" 2>&1 \
    || fail "updates/update-fisher.sh failed against the Fish fixture"
assert_log_line 'fish -c fisher update' "$fisher_case/invocations.log"

# Oh My Zsh invokes its checked-out upgrade script with silent verbosity.
omz_case="$TMP/mock-oh-my-zsh"
mkdir -p "$omz_case/home/.oh-my-zsh/.git" \
    "$omz_case/home/.oh-my-zsh/tools" "$omz_case/bin"
for command_name in dirname head; do
    ln -s "$(command -v "$command_name")" "$omz_case/bin/$command_name"
done
: >"$omz_case/home/.oh-my-zsh/tools/upgrade.sh"
make_logging_tool zsh "$omz_case/bin"
cat >"$omz_case/bin/git" <<'GIT_STUB'
#!/bin/bash
case "$*" in
    *'config --get remote.origin.url'*) echo 'https://github.com/ohmyzsh/ohmyzsh.git' ;;
    *'status --porcelain'*) ;;
    *) printf '%s\n' deadbee ;;
esac
GIT_STUB
chmod +x "$omz_case/bin/git"
: >"$omz_case/invocations.log"
/usr/bin/env -i HOME="$omz_case/home" PATH="$omz_case/bin" \
    UPDATE_TEST_LOG="$omz_case/invocations.log" \
    /bin/bash "$UPDATES_DIR/update-oh-my-zsh.sh" >"$omz_case/output.log" 2>&1 \
    || fail "updates/update-oh-my-zsh.sh failed against the Oh My Zsh fixture"
assert_log_line "zsh $omz_case/home/.oh-my-zsh/tools/upgrade.sh -v silent" \
    "$omz_case/invocations.log"

# Standalone binary updaters must reject binaries outside the repository's
# known installation layouts before invoking self-update.
for ownership_tool in restic rclone; do
    ownership_case="$TMP/mock-$ownership_tool-ownership"
    mkdir -p "$ownership_case/home" "$ownership_case/bin"
    ln -s "$(command -v dirname)" "$ownership_case/bin/dirname"
    ln -s "$(command -v readlink)" "$ownership_case/bin/readlink"
    make_logging_tool "$ownership_tool" "$ownership_case/bin"
    : >"$ownership_case/invocations.log"
    /usr/bin/env -i HOME="$ownership_case/home" PATH="$ownership_case/bin" \
        UPDATE_TEST_LOG="$ownership_case/invocations.log" \
        /bin/bash "$UPDATES_DIR/update-$ownership_tool.sh" \
        >"$ownership_case/output.log" 2>&1 \
        || fail "updates/update-$ownership_tool.sh failed its ownership rejection fixture"
    if grep -Eq 'self-update|selfupdate' "$ownership_case/invocations.log"; then
        fail "update-$ownership_tool invoked self-update for an unmanaged binary"
    fi
done

# Source updaters must not pull an arbitrary repository merely because it sits
# at the configured path.
source_owner_case="$TMP/mock-source-ownership"
mkdir -p "$source_owner_case/home/.pyenv/.git" \
    "$source_owner_case/home/.tmux/plugins/tpm/.git" \
    "$source_owner_case/home/.local/src/llama.cpp/.git" \
    "$source_owner_case/home/.local/src/llama.cpp/build" \
    "$source_owner_case/home/.rbenv/.git" \
    "$source_owner_case/home/.rbenv/plugins/ruby-build/.git" \
    "$source_owner_case/home/.oh-my-zsh/.git" \
    "$source_owner_case/home/.oh-my-zsh/tools" \
    "$source_owner_case/bin"
: >"$source_owner_case/home/.local/src/llama.cpp/build/CMakeCache.txt"
: >"$source_owner_case/home/.oh-my-zsh/tools/upgrade.sh"
ln -s "$(command -v dirname)" "$source_owner_case/bin/dirname"
make_logging_tool zsh "$source_owner_case/bin"
cat >"$source_owner_case/bin/git" <<'GIT_STUB'
#!/bin/bash
printf 'git %s\n' "$*" >>"$UPDATE_TEST_LOG"
case "$*" in
    *'config --get remote.origin.url'*) echo 'https://example.invalid/not-upstream.git' ;;
esac
GIT_STUB
chmod +x "$source_owner_case/bin/git"
for source_updater in pyenv rbenv tpm llama-cpp oh-my-zsh; do
    : >"$source_owner_case/invocations.log"
    /usr/bin/env -i HOME="$source_owner_case/home" PATH="$source_owner_case/bin" \
        UPDATE_TEST_LOG="$source_owner_case/invocations.log" \
        /bin/bash "$UPDATES_DIR/update-${source_updater}.sh" \
        >"$source_owner_case/${source_updater}.log" 2>&1 \
        || fail "update-$source_updater failed its upstream-ownership rejection fixture"
    if grep -Fq ' pull ' "$source_owner_case/invocations.log"; then
        fail "update-$source_updater pulled a checkout with an untrusted origin"
    fi
    if grep -Fq 'upgrade.sh' "$source_owner_case/invocations.log"; then
        fail "update-$source_updater executed checkout code from an untrusted origin"
    fi
done

# A failed llama.cpp build can touch several executables before returning.
# Restore the complete previous bin directory, not only llama-cli.
llama_case="$TMP/mock-llama-rollback"
llama_dir="$llama_case/home/.local/src/llama.cpp"
llama_bin_dir="$llama_dir/build/bin"
mkdir -p "$llama_dir/.git" "$llama_bin_dir" "$llama_case/bin"
: >"$llama_dir/build/CMakeCache.txt"
cat >"$llama_bin_dir/llama-cli" <<'LLAMA_OLD'
#!/bin/bash
echo 'llama-cli old-version'
LLAMA_OLD
cat >"$llama_bin_dir/llama-server" <<'LLAMA_SERVER_OLD'
#!/bin/bash
echo 'llama-server old-version'
LLAMA_SERVER_OLD
chmod +x "$llama_bin_dir/llama-cli" "$llama_bin_dir/llama-server"
for command_name in cp dirname head mktemp mv nproc rm; do
    ln -s "$(command -v "$command_name")" "$llama_case/bin/$command_name"
done
cat >"$llama_case/bin/git" <<'GIT_STUB'
#!/bin/bash
printf 'git %s\n' "$*" >>"$UPDATE_TEST_LOG"
case "$*" in
    *'config --get remote.origin.url'*) echo 'https://github.com/ggerganov/llama.cpp.git' ;;
    *'status --porcelain'*) ;;
    *'rev-parse --short HEAD'*) echo 'deadbee' ;;
    *'rev-parse HEAD'*) echo 'deadbeefdeadbeefdeadbeefdeadbeefdeadbeef' ;;
esac
GIT_STUB
cat >"$llama_case/bin/cmake" <<'CMAKE_STUB'
#!/bin/bash
/bin/cat >"$UPDATE_TEST_LLAMA_BIN/llama-cli" <<'LLAMA_NEW'
#!/bin/bash
echo 'llama-cli incomplete-new-version'
LLAMA_NEW
/bin/cat >"$UPDATE_TEST_LLAMA_BIN/llama-server" <<'LLAMA_SERVER_NEW'
#!/bin/bash
echo 'llama-server incomplete-new-version'
LLAMA_SERVER_NEW
/bin/chmod +x "$UPDATE_TEST_LLAMA_BIN/llama-cli" "$UPDATE_TEST_LLAMA_BIN/llama-server"
exit 1
CMAKE_STUB
chmod +x "$llama_case/bin/git" "$llama_case/bin/cmake"
: >"$llama_case/invocations.log"
if /usr/bin/env -i HOME="$llama_case/home" PATH="$llama_case/bin" \
    UPDATE_TEST_LOG="$llama_case/invocations.log" \
    UPDATE_TEST_LLAMA_BIN="$llama_bin_dir" \
    /bin/bash "$UPDATES_DIR/update-llama-cpp.sh" \
    >"$llama_case/output.log" 2>&1; then
    fail "update-llama-cpp accepted a failed partial build"
fi
"$llama_bin_dir/llama-cli" --version | grep -Fqx 'llama-cli old-version' \
    || fail "update-llama-cpp did not restore the previous llama-cli"
"$llama_bin_dir/llama-server" --version | grep -Fqx 'llama-server old-version' \
    || fail "update-llama-cpp did not restore the complete previous binary set"
grep -Fq "git -C $llama_dir reset --keep deadbeefdeadbeefdeadbeefdeadbeefdeadbeef" \
    "$llama_case/invocations.log" \
    || fail "update-llama-cpp did not restore its previous source revision"
if find "$llama_dir/build" -maxdepth 1 -name '.rollback.*' | grep -q .; then
    fail "update-llama-cpp left rollback staging after a successful restore"
fi

# AWS publishes a detached signature for its privileged ZIP installer. Lock the
# embedded key fingerprint and ensure verification precedes extraction/root use.
aws_source="$UPDATES_DIR/update-aws-cli.sh"
aws_key="$TMP/aws-cli-key.asc"
aws_show_key_home="$TMP/aws-show-key-gnupg"
awk '/^-----BEGIN PGP PUBLIC KEY BLOCK-----$/ { capture=1 } capture { print } /^-----END PGP PUBLIC KEY BLOCK-----$/ { exit }' \
    "$aws_source" >"$aws_key"
mkdir -m 700 "$aws_show_key_home"
aws_fingerprint=$(gpg --batch --homedir "$aws_show_key_home" \
    --show-keys --with-colons --fingerprint "$aws_key" 2>/dev/null \
    | awk -F: '$1 == "fpr" { print toupper($10); exit }')
[[ "$aws_fingerprint" == 'FB5DB77FD5C118B80511ADA8A6310ACC4672475C' ]] \
    || fail "update-aws-cli embeds an unexpected signing key fingerprint"
aws_verify_line=$(grep -nF "gpg --batch --homedir \"\$AWS_GNUPGHOME\" --verify" "$aws_source" | cut -d: -f1)
aws_unzip_line=$(grep -nF "unzip -q \"\$AWS_ZIP\"" "$aws_source" | cut -d: -f1)
aws_sudo_line=$(grep -nF "sudo \"\$AWS_TMP_DIR/aws/install\"" "$aws_source" | cut -d: -f1)
[[ -n "$aws_verify_line" && -n "$aws_unzip_line" && -n "$aws_sudo_line" \
    && "$aws_verify_line" -lt "$aws_unzip_line" && "$aws_unzip_line" -lt "$aws_sudo_line" ]] \
    || fail "update-aws-cli does not verify its detached signature before extraction and root execution"
grep -Fq "\"\${AWS_DOWNLOAD_URL}.sig\"" "$aws_source" \
    || fail "update-aws-cli does not download the matching detached signature"

starship_case="$TMP/mock-starship-release"
mkdir -p "$starship_case/home/.local/bin" "$starship_case/bin"
for command_name in awk cat dirname gzip head install mktemp mv rm sha256sum tar uname; do
    ln -s "$(command -v "$command_name")" "$starship_case/bin/$command_name"
done
make_logging_tool starship "$starship_case/home/.local/bin"
cat >"$starship_case/bin/curl" <<'CURL_STUB'
#!/bin/bash
printf 'curl %s\n' "$*" >>"$UPDATE_TEST_LOG"
if [[ " $* " == *" -w "* ]]; then
    printf '%s\n' 'https://github.com/starship/starship/releases/tag/v9.9.9'
    exit 0
fi
output=''
while [[ "$#" -gt 0 ]]; do
    if [[ "$1" == '-o' ]]; then
        output="$2"
        break
    fi
    shift
done
[[ -n "$output" ]] || exit 64
case "$output" in
    *.sha256)
        archive=${output%.sha256}
        digest=$("$REAL_SHA256SUM" "$archive")
        digest=${digest%% *}
        if [[ "${UPDATE_TEST_BAD_SHA:-0}" == 1 ]]; then
            digest=0000000000000000000000000000000000000000000000000000000000000000
        fi
        printf '%s  %s\n' "$digest" "${archive##*/}" >"$output"
        ;;
    *)
        payload_dir="${output}.contents"
        /bin/mkdir -p "$payload_dir"
        cat >"$payload_dir/starship" <<'STARSHIP_STUB'
#!/bin/bash
printf 'starship %s\n' "$*" >>"$UPDATE_TEST_LOG"
if [[ "${1:-}" == '--version' ]]; then
    echo 'starship new-version'
fi
STARSHIP_STUB
        /bin/chmod +x "$payload_dir/starship"
        "$REAL_TAR" -czf "$output" -C "$payload_dir" starship
        /bin/rm -rf "$payload_dir"
        ;;
esac
CURL_STUB
chmod +x "$starship_case/bin/curl"
: >"$starship_case/invocations.log"

# A bad upstream digest must fail before the existing binary is replaced.
if /usr/bin/env -i HOME="$starship_case/home" PATH="$starship_case/bin" \
    REAL_SHA256SUM="$(command -v sha256sum)" REAL_TAR="$(command -v tar)" \
    UPDATE_TEST_BAD_SHA=1 UPDATE_TEST_LOG="$starship_case/invocations.log" \
    /bin/bash "$UPDATES_DIR/update-starship.sh" \
    >"$starship_case/bad-checksum.log" 2>&1; then
    fail "update-starship accepted a mismatched release checksum"
fi
grep -Fq 'starship test-version' "$starship_case/home/.local/bin/starship" \
    || fail "update-starship replaced the existing binary after checksum failure"

: >"$starship_case/invocations.log"
/usr/bin/env -i HOME="$starship_case/home" PATH="$starship_case/bin" \
    REAL_SHA256SUM="$(command -v sha256sum)" REAL_TAR="$(command -v tar)" \
    UPDATE_TEST_LOG="$starship_case/invocations.log" \
    /bin/bash "$UPDATES_DIR/update-starship.sh" >"$starship_case/output.log" 2>&1 \
    || { sed -n '1,120p' "$starship_case/output.log" >&2; fail "updates/update-starship.sh failed against the verified release fixture"; }
grep -Fq 'starship new-version' <(
    /usr/bin/env -i UPDATE_TEST_LOG="$starship_case/invocations.log" \
        "$starship_case/home/.local/bin/starship" --version
) \
    || fail "update-starship did not atomically activate the validated release binary"
grep -Fq '.tar.gz.sha256' "$starship_case/invocations.log" \
    || fail "update-starship did not download the release checksum"

# Claude is installed from Anthropic's APT repository in this project. Verify
# that its updater refreshes package metadata and targets only claude-code.
claude_case="$TMP/mock-claude-apt"
mkdir -p "$claude_case/home" "$claude_case/bin"
for command_name in dirname grep; do
    ln -s "$(command -v "$command_name")" "$claude_case/bin/$command_name"
done
make_logging_tool claude "$claude_case/bin"
cat >"$claude_case/bin/dpkg-query" <<'DPKG_STUB'
#!/bin/bash
case "${1:-}" in
    -W) echo 'install ok installed' ;;
    -S) echo "claude-code: ${2:-/usr/bin/claude}" ;;
    *) exit 1 ;;
esac
DPKG_STUB
cat >"$claude_case/bin/sudo" <<'SUDO_STUB'
#!/bin/bash
printf 'sudo %s\n' "$*" >>"$UPDATE_TEST_LOG"
SUDO_STUB
chmod +x "$claude_case/bin/dpkg-query" "$claude_case/bin/sudo"
: >"$claude_case/invocations.log"
/usr/bin/env -i HOME="$claude_case/home" PATH="$claude_case/bin" \
    UPDATE_TEST_LOG="$claude_case/invocations.log" \
    /bin/bash "$UPDATES_DIR/update-claude.sh" >"$claude_case/output.log" 2>&1 \
    || fail "updates/update-claude.sh failed against isolated APT stubs"
assert_log_line 'sudo apt-get update' "$claude_case/invocations.log"
assert_log_line 'sudo apt-get install -y --only-upgrade claude-code' "$claude_case/invocations.log"

# Claude Code also ships as a global npm package. With no APT package owning
# the executable, the updater must fall through to npm provenance and select
# the release matching the configured channel rather than skipping outright.
claude_npm_case="$TMP/mock-claude-npm"
claude_npm_prefix="$claude_npm_case/home/.npm-global"
claude_npm_root="$claude_npm_prefix/lib/node_modules"
mkdir -p "$claude_npm_prefix/bin" "$claude_npm_root/@anthropic-ai/claude-code" \
    "$claude_npm_case/bin"
for command_name in dirname readlink grep; do
    ln -s "$(command -v "$command_name")" "$claude_npm_case/bin/$command_name"
done
make_logging_tool claude "$claude_npm_prefix/bin"
cat >"$claude_npm_case/bin/npm" <<NPM_STUB
#!/bin/bash
printf 'npm %s\n' "\$*" >>"\$UPDATE_TEST_LOG"
case "\$*" in
    'config get prefix') printf '%s\n' '$claude_npm_prefix' ;;
    'root -g') printf '%s\n' '$claude_npm_root' ;;
esac
NPM_STUB
chmod +x "$claude_npm_case/bin/npm"

: >"$claude_npm_case/invocations.log"
/usr/bin/env -i HOME="$claude_npm_case/home" \
    PATH="$claude_npm_prefix/bin:$claude_npm_case/bin" \
    UPDATE_TEST_LOG="$claude_npm_case/invocations.log" \
    /bin/bash "$UPDATES_DIR/update-claude.sh" >"$claude_npm_case/output.log" 2>&1 \
    || fail "updates/update-claude.sh failed against the owned npm fixture"
assert_log_line 'npm install -g @anthropic-ai/claude-code@stable' \
    "$claude_npm_case/invocations.log"
if grep -Fq 'apt-get' "$claude_npm_case/invocations.log"; then
    fail "update-claude reached the APT path for an npm-owned installation"
fi

# The channel knob that picks ai/claude.sh's APT repo picks the npm dist-tag.
: >"$claude_npm_case/invocations.log"
/usr/bin/env -i HOME="$claude_npm_case/home" \
    PATH="$claude_npm_prefix/bin:$claude_npm_case/bin" \
    UPDATE_TEST_LOG="$claude_npm_case/invocations.log" CLAUDE_CHANNEL=latest \
    /bin/bash "$UPDATES_DIR/update-claude.sh" >"$claude_npm_case/latest.log" 2>&1 \
    || fail "updates/update-claude.sh failed for the latest npm channel"
assert_log_line 'npm install -g @anthropic-ai/claude-code@latest' \
    "$claude_npm_case/invocations.log"

# An npm prefix that owns no claude package must not be upgraded into one.
claude_foreign_case="$TMP/mock-claude-foreign"
claude_foreign_prefix="$claude_foreign_case/home/.npm-global"
claude_foreign_root="$claude_foreign_prefix/lib/node_modules"
mkdir -p "$claude_foreign_prefix/bin" "$claude_foreign_root" "$claude_foreign_case/bin"
for command_name in dirname readlink grep; do
    ln -s "$(command -v "$command_name")" "$claude_foreign_case/bin/$command_name"
done
make_logging_tool claude "$claude_foreign_case/bin"
cat >"$claude_foreign_case/bin/npm" <<NPM_STUB
#!/bin/bash
printf 'npm %s\n' "\$*" >>"\$UPDATE_TEST_LOG"
case "\$*" in
    'config get prefix') printf '%s\n' '$claude_foreign_prefix' ;;
    'root -g') printf '%s\n' '$claude_foreign_root' ;;
esac
NPM_STUB
chmod +x "$claude_foreign_case/bin/npm"
: >"$claude_foreign_case/invocations.log"
/usr/bin/env -i HOME="$claude_foreign_case/home" \
    PATH="$claude_foreign_case/bin" \
    UPDATE_TEST_LOG="$claude_foreign_case/invocations.log" \
    /bin/bash "$UPDATES_DIR/update-claude.sh" >"$claude_foreign_case/output.log" 2>&1 \
    || fail "updates/update-claude.sh did not skip an unowned Claude installation"
if grep -Fq 'npm install' "$claude_foreign_case/invocations.log"; then
    fail "update-claude installed over a Claude executable it does not own"
fi
grep -Eqi 'skip' "$claude_foreign_case/output.log" \
    || fail "update-claude did not explain why it skipped an unowned installation"

# Antigravity comes from Google's Artifact Registry APT repository. Its updater
# must target only that package and must read versions from the package
# database instead of launching the GUI binary. Ownership is proven by package
# status alone: /usr/bin/antigravity is a postinst symlink that dpkg does not
# track, so a `dpkg-query -S` guard would skip a genuine installation.
antigravity_case="$TMP/mock-antigravity-apt"
mkdir -p "$antigravity_case/home" "$antigravity_case/bin"
for command_name in dirname grep; do
    ln -s "$(command -v "$command_name")" "$antigravity_case/bin/$command_name"
done
make_logging_tool antigravity "$antigravity_case/bin"
cat >"$antigravity_case/bin/dpkg-query" <<'DPKG_STUB'
#!/bin/bash
case "${1:-}" in
    -W)
        case "${2:-}" in
            *Status*) echo 'install ok installed' ;;
            *Version*) echo '1.0.0-1763466940' ;;
            *) exit 1 ;;
        esac
        ;;
    *) exit 1 ;;
esac
DPKG_STUB
cat >"$antigravity_case/bin/sudo" <<'SUDO_STUB'
#!/bin/bash
printf 'sudo %s\n' "$*" >>"$UPDATE_TEST_LOG"
SUDO_STUB
chmod +x "$antigravity_case/bin/dpkg-query" "$antigravity_case/bin/sudo"
: >"$antigravity_case/invocations.log"
/usr/bin/env -i HOME="$antigravity_case/home" PATH="$antigravity_case/bin" \
    UPDATE_TEST_LOG="$antigravity_case/invocations.log" \
    /bin/bash "$UPDATES_DIR/update-antigravity.sh" >"$antigravity_case/output.log" 2>&1 \
    || fail "updates/update-antigravity.sh failed against isolated APT stubs"
assert_log_line 'sudo apt-get update' "$antigravity_case/invocations.log"
assert_log_line 'sudo apt-get install -y --only-upgrade antigravity' "$antigravity_case/invocations.log"
grep -Fq '1.0.0-1763466940' "$antigravity_case/output.log" \
    || fail "update-antigravity did not report the packaged version"
if grep -Fqx 'antigravity --version' "$antigravity_case/invocations.log"; then
    fail "update-antigravity launched the GUI binary to read a version"
fi

# VS Code extension maintenance is scoped to the code Debian package and must
# use the CLI's extension-only updater.
vscode_case="$TMP/mock-vscode-extensions"
mkdir -p "$vscode_case/home" "$vscode_case/bin"
for command_name in dirname grep head; do
    ln -s "$(command -v "$command_name")" "$vscode_case/bin/$command_name"
done
make_logging_tool code "$vscode_case/bin"
cat >"$vscode_case/bin/dpkg-query" <<'DPKG_STUB'
#!/bin/bash
case "${1:-}" in
    -W) echo 'install ok installed' ;;
    -S) echo "code: ${2:-/usr/bin/code}" ;;
    *) exit 1 ;;
esac
DPKG_STUB
cat >"$vscode_case/bin/sudo" <<'SUDO_STUB'
#!/bin/bash
printf 'sudo %s\n' "$*" >>"$UPDATE_TEST_LOG"
SUDO_STUB
chmod +x "$vscode_case/bin/dpkg-query" "$vscode_case/bin/sudo"
: >"$vscode_case/invocations.log"
/usr/bin/env -i HOME="$vscode_case/home" PATH="$vscode_case/bin" \
    UPDATE_TEST_LOG="$vscode_case/invocations.log" \
    /bin/bash "$UPDATES_DIR/update-vscode-extensions.sh" \
    >"$vscode_case/output.log" 2>&1 \
    || fail "updates/update-vscode-extensions.sh failed against the code fixture"
assert_log_line 'code --update-extensions' "$vscode_case/invocations.log"

: >"$vscode_case/invocations.log"
/usr/bin/env -i HOME="$vscode_case/home" PATH="$vscode_case/bin" \
    UPDATE_TEST_LOG="$vscode_case/invocations.log" \
    /bin/bash "$UPDATES_DIR/update-vscode.sh" \
    >"$vscode_case/package-output.log" 2>&1 \
    || fail "updates/update-vscode.sh failed against the code APT fixture"
assert_log_line 'sudo apt-get update' "$vscode_case/invocations.log"
assert_log_line 'sudo apt-get install -y --only-upgrade code' \
    "$vscode_case/invocations.log"

# Release-replacement wrappers delegate to the checksum-verifying installers
# using private force flags rather than running mutable remote scripts.
grep -Fq 'UPI_LAZYDOCKER_UPDATE=1' "$UPDATES_DIR/update-lazydocker.sh" \
    || fail "update-lazydocker does not delegate to the verified installer"
grep -Fq 'UPI_JUST_UPDATE=1' "$UPDATES_DIR/update-just.sh" \
    || fail "update-just does not delegate to the verified installer"
grep -Fq 'UPI_NVIM_UPDATE=1' "$UPDATES_DIR/update-nvim.sh" \
    || fail "update-nvim does not delegate to the rollback-capable installer"

for verified_release_updater in ctop gitleaks yq; do
    verified_source="$UPDATES_DIR/update-${verified_release_updater}.sh"
    grep -Fq 'sha256sum --check --quiet' "$verified_source" \
        || fail "update-$verified_release_updater does not verify its release checksum"
    grep -Fq 'mktemp' "$verified_source" \
        || fail "update-$verified_release_updater does not create a collision-safe stage"
    grep -Fq 'STAGED' "$verified_source" \
        || fail "update-$verified_release_updater does not validate a staged binary"
    grep -Fq 'mv -f --' "$verified_source" \
        || fail "update-$verified_release_updater does not atomically activate its staged binary"
done

for delegated_installer in just lazydocker; do
    delegated_source="$REPO_ROOT/tools/${delegated_installer}.sh"
    grep -Fq 'stage.XXXXXX' "$delegated_source" \
        || fail "$delegated_installer installer does not create a sibling update stage"
    grep -Fq 'STAGE_VERSION=' "$delegated_source" \
        || fail "$delegated_installer installer does not validate the staged binary"
    grep -Fq "sudo mv -f \"\$STAGE\"" "$delegated_source" \
        || fail "$delegated_installer installer does not atomically activate its staged binary"
done

# NVM is sourced rather than discovered on PATH, so exercise its installation
# path with a function-only shim and confirm both required state changes.
nvm_case="$TMP/mock-nvm"
mkdir -p "$nvm_case/home/.nvm/.git" "$nvm_case/bin"
ln -s "$(command -v dirname)" "$nvm_case/bin/dirname"
cat >"$nvm_case/home/.nvm/nvm.sh" <<'NVM_STUB'
nvm() {
    printf 'nvm %s\n' "$*" >>"$UPDATE_TEST_LOG"
}
NVM_STUB
cat >"$nvm_case/bin/git" <<'GIT_STUB'
#!/bin/bash
printf 'git %s\n' "$*" >>"$UPDATE_TEST_LOG"
case "$*" in
    *'config --get remote.origin.url'*) echo 'https://github.com/nvm-sh/nvm.git' ;;
    *'status --porcelain'*) ;;
    *'rev-parse --short HEAD'*) echo 'deadbee' ;;
    *'rev-parse HEAD'*) echo 'deadbeefdeadbeefdeadbeefdeadbeefdeadbeef' ;;
    *'checkout --detach'*) [[ "${UPDATE_TEST_NVM_CHECKOUT_FAIL:-0}" != 1 ]] ;;
esac
GIT_STUB
chmod +x "$nvm_case/bin/git"
: >"$nvm_case/invocations.log"
/usr/bin/env -i HOME="$nvm_case/home" PATH="$nvm_case/bin" \
    UPI_NVM_LATEST_TAG=v9.9.9 \
    UPDATE_TEST_LOG="$nvm_case/invocations.log" \
    /bin/bash "$UPDATES_DIR/update-node.sh" >"$nvm_case/output.log" 2>&1 \
    || fail "updates/update-node.sh failed against the isolated NVM stub"
assert_log_line 'nvm install --lts' "$nvm_case/invocations.log"
assert_log_line 'nvm alias default lts/*' "$nvm_case/invocations.log"
assert_log_line "git -C $nvm_case/home/.nvm fetch --depth=1 origin refs/tags/v9.9.9:refs/tags/v9.9.9" \
    "$nvm_case/invocations.log"
assert_log_line "git -C $nvm_case/home/.nvm checkout --detach v9.9.9" \
    "$nvm_case/invocations.log"

if /usr/bin/env -i HOME="$nvm_case/home" PATH="$nvm_case/bin" \
    UPI_NVM_LATEST_TAG=v9.9.9 UPDATE_TEST_NVM_CHECKOUT_FAIL=1 \
    UPDATE_TEST_LOG="$nvm_case/invocations.log" \
    /bin/bash "$UPDATES_DIR/update-node.sh" >"$nvm_case/rollback-failure.log" 2>&1; then
    fail "update-node accepted a failed NVM checkout and failed rollback"
fi
grep -Fq 'NVM rollback failed' "$nvm_case/rollback-failure.log" \
    || fail "update-node hid an NVM rollback failure"
if grep -Fq 'restored the previous checkout' "$nvm_case/rollback-failure.log"; then
    fail "update-node falsely claimed a failed NVM rollback succeeded"
fi

# Copy update-all into a synthetic repository so it can execute controlled
# sibling scripts. The failing updater must not prevent a later updater from
# running, and the aggregate command must still return failure with a summary.
aggregate_case="$TMP/aggregate"
mkdir -p "$aggregate_case/repo/updates" "$aggregate_case/repo/lib" \
    "$aggregate_case/home" "$aggregate_case/bin"
cp "$UPDATES_DIR/update-all.sh" "$aggregate_case/repo/updates/update-all.sh"
cp "$REPO_ROOT/lib/config.bash" "$aggregate_case/repo/lib/config.bash"
for command_name in dirname basename bash; do
    ln -s "$(command -v "$command_name")" "$aggregate_case/bin/$command_name"
done

cat >"$aggregate_case/repo/updates/catalog.txt" <<'CATALOG'
update-all.sh|updates/catalog.txt|aggregate
update-a-success.sh|fixture|fixture
update-b-fail.sh|fixture|fixture
update-c-after.sh|fixture|fixture
CATALOG

for fixture in a-success b-fail c-after; do
    fixture_path="$aggregate_case/repo/updates/update-$fixture.sh"
    cat >"$fixture_path" <<FIXTURE
#!/bin/bash
printf '%s\n' '$fixture' >>"\$UPDATE_TEST_LOG"
FIXTURE
    if [[ "$fixture" == b-fail ]]; then
        echo 'exit 23' >>"$fixture_path"
    fi
    chmod +x "$fixture_path"
done

cat >"$aggregate_case/repo/updates/update-z-rogue.sh" <<'FIXTURE'
#!/bin/bash
printf '%s\n' 'z-rogue' >>"$UPDATE_TEST_LOG"
FIXTURE
chmod +x "$aggregate_case/repo/updates/update-z-rogue.sh"

: >"$aggregate_case/invocations.log"
set +e
/usr/bin/env -i HOME="$aggregate_case/home" PATH="$aggregate_case/bin" \
    UPDATE_TEST_LOG="$aggregate_case/invocations.log" \
    /bin/bash "$aggregate_case/repo/updates/update-all.sh" \
    >"$aggregate_case/output.log" 2>&1
aggregate_status=$?
set -e

[[ "$aggregate_status" -eq 1 ]] \
    || fail "update-all returned $aggregate_status instead of 1 after a child failure"
assert_log_line 'a-success' "$aggregate_case/invocations.log"
assert_log_line 'b-fail' "$aggregate_case/invocations.log"
assert_log_line 'c-after' "$aggregate_case/invocations.log"
if grep -Fq 'z-rogue' "$aggregate_case/invocations.log"; then
    fail "update-all executed an updater that was not in updates/catalog.txt"
fi
grep -Fq '1 updater(s) failed: update-b-fail.sh' "$aggregate_case/output.log" \
    || fail "update-all did not summarize the failed updater"

echo "✅ updater scripts exist, parse, skip safely, and honor mocked update contracts"
