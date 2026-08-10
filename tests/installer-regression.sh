#!/bin/bash
set -euo pipefail

if [ -z "${BASH_VERSION:-}" ]; then
    exec /bin/bash "$0" "$@"
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_TMP=$(mktemp -d)
trap 'rm -rf "$TEST_TMP"' EXIT

fail() {
    echo "❌ $*" >&2
    exit 1
}

assert_contains() {
    local file="$1"
    local expected="$2"
    grep -qF -- "$expected" "$file" || fail "$file did not contain: $expected"
}

make_npm_stubs() {
    local bin="$1"
    mkdir -p "$bin"
    ln -s /usr/bin/cat "$bin/cat"
    ln -s /usr/bin/chmod "$bin/chmod"
    ln -s /usr/bin/cut "$bin/cut"
    ln -s /usr/bin/dirname "$bin/dirname"
    cat > "$bin/node" <<'EOF'
#!/bin/bash
    echo v22.19.0
EOF
    cat > "$bin/npm" <<'EOF'
#!/bin/bash
echo "$0 $*" >> "$STUB_LOG"
if [ "${1:-}" = config ]; then
    echo "$NPM_PREFIX"
    exit 0
fi
case "$*" in
    *google/gemini-cli*) target=gemini ;;
    *modelcontextprotocol/inspector*) target=mcp-inspector ;;
    *cline@*) target=cline ;;
    *) exit 2 ;;
esac
cat > "$STUB_BIN/$target" <<INNER
#!/bin/bash
echo stub-version
INNER
chmod +x "$STUB_BIN/$target"
EOF
    cat > "$bin/sudo" <<'EOF'
#!/bin/bash
echo "sudo $*" >> "$STUB_LOG"
"$@"
EOF
    chmod +x "$bin/node" "$bin/npm" "$bin/sudo"
}

test_npm_installers() {
    local name script package bin prefix log output install_count
    for entry in \
        "gemini|$REPO_ROOT/ai/gemini.sh|@google/gemini-cli" \
        "cline|$REPO_ROOT/ai/cline.sh|cline@latest" \
        "mcp-inspector|$REPO_ROOT/ai/mcp-inspector.sh|@modelcontextprotocol/inspector@latest"; do
        IFS='|' read -r name script package <<< "$entry"

        bin="$TEST_TMP/${name}-user-bin"
        prefix="$TEST_TMP/home/.local/${name}-prefix"
        log="$TEST_TMP/${name}-user.log"
        output="$TEST_TMP/${name}-user.out"
        mkdir -p "$TEST_TMP/home"
        make_npm_stubs "$bin"
        STUB_BIN="$bin" STUB_LOG="$log" NPM_PREFIX="$prefix" HOME="$TEST_TMP/home" \
            PATH="$bin:/usr/bin:/bin" /bin/bash "$script" > "$output" 2>&1
        assert_contains "$log" "$bin/npm install -g $package"
        if grep -q '^sudo ' "$log"; then
            fail "$name used sudo for a writable user prefix"
        fi
        STUB_BIN="$bin" STUB_LOG="$log" NPM_PREFIX="$prefix" HOME="$TEST_TMP/home" \
            PATH="$bin:/usr/bin:/bin" /bin/bash "$script" >> "$output" 2>&1
        install_count=$(grep -c 'npm install -g ' "$log")
        [ "$install_count" -eq 1 ] || fail "$name invoked npm again on its second run"

        bin="$TEST_TMP/${name}-system-bin"
        log="$TEST_TMP/${name}-system.log"
        output="$TEST_TMP/${name}-system.out"
        make_npm_stubs "$bin"
        STUB_BIN="$bin" STUB_LOG="$log" NPM_PREFIX="/proc/installer-prefix" HOME="$TEST_TMP/home" \
            PATH="$bin:/usr/bin:/bin" /bin/bash "$script" > "$output" 2>&1
        assert_contains "$log" "$bin/npm install -g $package"
        if [ "$name" = gemini ]; then
            assert_contains "$log" "sudo $bin/npm install -g $package"
        else
            assert_contains "$log" "sudo env PATH="
        fi
    done
}

make_remote_installer_stub() {
    local bin="$1"
    mkdir -p "$bin"
    cat > "$bin/dpkg" <<'EOF'
#!/bin/bash
if [ "${1:-}" = -s ] && [ "${2:-}" = python3-venv ]; then
    exit 0
fi
exec /usr/bin/dpkg "$@"
EOF
    cat > "$bin/curl" <<'EOF'
#!/bin/bash
out=""
url=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        -o) out="$2"; shift 2 ;;
        -*) shift ;;
        *) url="$1"; shift ;;
    esac
done
[ -n "$out" ] || exit 2
echo "curl $url" >> "$STUB_LOG"
cat > "$out" <<'INSTALLER'
#!/bin/bash
echo "installer CODEX_RELEASE=${CODEX_RELEASE:-} CODEX_NON_INTERACTIVE=${CODEX_NON_INTERACTIVE:-} CONFIGURE=${CONFIGURE:-} PREFIX=${PREFIX:-} VERSION=${VERSION:-} args=$*" >> "$STUB_LOG"
mkdir -p "$(dirname "$STUB_INSTALL_TARGET")"
cat > "$STUB_INSTALL_TARGET" <<'BIN'
#!/bin/bash
echo stub-version
BIN
chmod +x "$STUB_INSTALL_TARGET"
INSTALLER
EOF
    chmod +x "$bin/curl" "$bin/dpkg"
}

test_remote_ai_installers() {
    local name script url bin home target log output curl_count marker_count
    for entry in \
        "codex:$REPO_ROOT/ai/codex.sh:https://chatgpt.com/codex/install.sh" \
        "copilot:$REPO_ROOT/ai/github-copilot.sh:https://gh.io/copilot-install" \
        "hf:$REPO_ROOT/ai/huggingface-cli.sh:https://hf.co/cli/install.sh" \
        "aider:$REPO_ROOT/ai/aider.sh:https://aider.chat/install.sh" \
        "goose:$REPO_ROOT/ai/goose.sh:https://github.com/aaif-goose/goose/releases/download/stable/download_cli.sh" \
        "qwen:$REPO_ROOT/ai/qwen-code.sh:https://qwen-code-assets.oss-cn-hangzhou.aliyuncs.com/installation/install-qwen-standalone.sh" \
        "cursor-agent:$REPO_ROOT/ai/cursor-agent.sh:https://cursor.com/install" \
        "vibe:$REPO_ROOT/ai/mistral-vibe.sh:https://mistral.ai/vibe/install.sh" \
        "fabric:$REPO_ROOT/ai/fabric.sh:https://raw.githubusercontent.com/danielmiessler/Fabric/main/scripts/installer/install.sh"; do
        IFS=: read -r name script url <<< "$entry"
        bin="$TEST_TMP/${name}-installer-bin"
        home="$TEST_TMP/${name}-installer-home"
        target="$home/.local/bin/$name"
        log="$TEST_TMP/${name}-installer.log"
        output="$TEST_TMP/${name}-installer.out"
        mkdir -p "$home"
        make_remote_installer_stub "$bin"

        STUB_INSTALL_TARGET="$target" STUB_LOG="$log" HOME="$home" \
            PATH="$bin:/usr/bin:/bin" /bin/bash "$script" > "$output" 2>&1
        [ -x "$target" ] || fail "$name installer did not create its CLI"
        assert_contains "$log" "curl $url"

        STUB_INSTALL_TARGET="$target" STUB_LOG="$log" HOME="$home" \
            PATH="$bin:/usr/bin:/bin" /bin/bash "$script" >> "$output" 2>&1
        curl_count=$(grep -c '^curl ' "$log")
        [ "$curl_count" -eq 1 ] || fail "$name installer downloaded again on its second run"
        case "$name" in
            copilot)
                marker_count=$(grep -cF '# ~/.local/bin (added by github-copilot.sh)' "$home/.profile")
                [ "$marker_count" -eq 1 ] || fail "Copilot PATH configuration was not idempotent"
                ;;
            aider)
                marker_count=$(grep -cF '# ~/.local/bin (added by aider.sh)' "$home/.profile")
                [ "$marker_count" -eq 1 ] || fail "Aider PATH configuration was not idempotent"
                ;;
            goose|cursor-agent|vibe|fabric)
                marker_count=$(grep -cF "# ~/.local/bin (added by ${script##*/})" "$home/.profile")
                [ "$marker_count" -eq 1 ] || fail "$name PATH configuration was not idempotent"
                ;;
            qwen)
                marker_count=$(grep -cF '# Qwen Code paths (added by qwen-code.sh)' "$home/.profile")
                [ "$marker_count" -eq 1 ] || fail "Qwen PATH configuration was not idempotent"
                ;;
        esac
    done

    assert_contains "$TEST_TMP/codex-installer.log" "CODEX_NON_INTERACTIVE=true"
    assert_contains "$TEST_TMP/copilot-installer.log" "PREFIX=$TEST_TMP/copilot-installer-home/.local"
    assert_contains "$TEST_TMP/hf-installer.log" "args=--exclude-skill"
    assert_contains "$TEST_TMP/goose-installer.log" "CONFIGURE=false"
}

make_pipx_stub() {
    local bin="$1"
    mkdir -p "$bin"
    cat > "$bin/pipx" <<'EOF'
#!/bin/bash
echo "pipx $*" >> "$STUB_LOG"
[ "${1:-}" = runpip ] && exit 0
[ "${1:-}" = install ] || exit 2
case "${2:-}" in
    llm|llm==*) target=llm ;;
    litellm*) target=litellm ;;
    *) exit 2 ;;
esac
mkdir -p "$HOME/.local/bin"
cat > "$HOME/.local/bin/$target" <<'BIN'
#!/bin/bash
echo stub-version
BIN
chmod +x "$HOME/.local/bin/$target"
EOF
    chmod +x "$bin/pipx"
}

test_pipx_ai_installers() {
    local name script version_var version_value package bin home log output marker_count install_count
    for entry in \
        "llm|$REPO_ROOT/ai/llm-cli.sh|LLM_VERSION|1.2.3|llm==1.2.3" \
        "litellm|$REPO_ROOT/ai/litellm.sh|LITELLM_VERSION|latest|litellm[proxy]"; do
        IFS='|' read -r name script version_var version_value package <<< "$entry"
        bin="$TEST_TMP/${name}-pipx-bin"
        home="$TEST_TMP/${name}-pipx-home"
        log="$TEST_TMP/${name}-pipx.log"
        output="$TEST_TMP/${name}-pipx.out"
        mkdir -p "$home"
        make_pipx_stub "$bin"

        env "$version_var=$version_value" STUB_LOG="$log" HOME="$home" PATH="$bin:/usr/bin:/bin" \
            /bin/bash "$script" > "$output" 2>&1
        assert_contains "$log" "pipx install $package"
        if [ "$name" = litellm ]; then
            assert_contains "$log" "pipx runpip litellm install --upgrade fastapi>=0.136.3,<1.0 starlette>=1.0.1,<2.0"
        fi

        env "$version_var=$version_value" STUB_LOG="$log" HOME="$home" PATH="$bin:/usr/bin:/bin" \
            /bin/bash "$script" >> "$output" 2>&1
        install_count=$(grep -c '^pipx install ' "$log")
        [ "$install_count" -eq 1 ] || fail "$name invoked pipx again on its second run"
        marker_count=$(grep -cF "# ~/.local/bin (added by ${script##*/})" "$home/.profile")
        [ "$marker_count" -eq 1 ] || fail "$name PATH configuration was not idempotent"
    done
}

test_claude_apt_installer() {
    local bin="$TEST_TMP/claude-apt-bin"
    local home="$TEST_TMP/claude-apt-home"
    local log="$TEST_TMP/claude-apt.log"
    local output="$TEST_TMP/claude-apt.out"
    local curl_count
    mkdir -p "$bin" "$home"
    cat > "$bin/curl" <<'EOF'
#!/bin/bash
out=""
url=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        -o) out="$2"; shift 2 ;;
        -*) shift ;;
        *) url="$1"; shift ;;
    esac
done
echo "curl $url" >> "$STUB_LOG"
printf 'test-key\n' > "$out"
EOF
    cat > "$bin/gpg" <<'EOF'
#!/bin/bash
echo 'fpr:::::::::31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE:'
EOF
    cat > "$bin/sudo" <<'EOF'
#!/bin/bash
echo "sudo $*" >> "$STUB_LOG"
if [ "${1:-}" = tee ]; then
    input=$(cat)
    echo "stdin $input" >> "$STUB_LOG"
    exit 0
fi
if [[ "$*" == *"apt-get install -y claude-code"* ]]; then
    cat > "$STUB_BIN/claude" <<'BIN'
#!/bin/bash
echo stub-version
BIN
    chmod +x "$STUB_BIN/claude"
fi
exit 0
EOF
    chmod +x "$bin/curl" "$bin/gpg" "$bin/sudo"

    STUB_BIN="$bin" STUB_LOG="$log" HOME="$home" CLAUDE_CHANNEL=latest \
        PATH="$bin:/usr/bin:/bin" /bin/bash "$REPO_ROOT/ai/claude.sh" > "$output" 2>&1
    assert_contains "$log" "downloads.claude.ai/keys/claude-code.asc"
    assert_contains "$log" "https://downloads.claude.ai/claude-code/apt/latest latest main"
    [ -x "$bin/claude" ] || fail "Claude APT installer did not install the CLI"

    STUB_BIN="$bin" STUB_LOG="$log" HOME="$home" CLAUDE_CHANNEL=latest \
        PATH="$bin:/usr/bin:/bin" /bin/bash "$REPO_ROOT/ai/claude.sh" >> "$output" 2>&1
    curl_count=$(grep -c '^curl ' "$log")
    [ "$curl_count" -eq 1 ] || fail "Claude installer downloaded its key again on the second run"

    if STUB_BIN="$bin" STUB_LOG="$log" HOME="$home" CLAUDE_CHANNEL=preview \
        PATH="$bin:/usr/bin:/bin" /bin/bash "$REPO_ROOT/ai/claude.sh" \
        > "$TEST_TMP/claude-invalid.out" 2>&1; then
        fail "Claude installer accepted an unsupported channel"
    fi
    assert_contains "$TEST_TMP/claude-invalid.out" "Unsupported CLAUDE_CHANNEL"
}

test_architecture_guards() {
    local script name bin log output
    for entry in \
        "chrome:$REPO_ROOT/apps/browsers.sh" \
        "warp:$REPO_ROOT/apps/warp.sh"; do
        IFS=: read -r name script <<< "$entry"
        bin="$TEST_TMP/${name}-arch-bin"
        log="$TEST_TMP/${name}-arch.log"
        output="$TEST_TMP/${name}-arch.out"
        mkdir -p "$bin"
        ln -s /usr/bin/dirname "$bin/dirname"
        cat > "$bin/dpkg" <<'EOF'
#!/bin/bash
echo arm64
EOF
        cat > "$bin/sudo" <<'EOF'
#!/bin/bash
echo "sudo $*" >> "$STUB_LOG"
exit 99
EOF
        cat > "$bin/wget" <<'EOF'
#!/bin/bash
echo "wget $*" >> "$STUB_LOG"
exit 99
EOF
        chmod +x "$bin/dpkg" "$bin/sudo" "$bin/wget"
        if STUB_LOG="$log" HOME="$TEST_TMP/home" PATH="$bin" /bin/bash "$script" \
            > "$output" 2>&1; then
            fail "$name installer accepted unsupported arm64"
        fi
        assert_contains "$output" "supports amd64 only"
        [ ! -e "$log" ] || fail "$name mutated the system or network before rejecting arm64"
    done
}

test_system_info_optional_failure() {
    local bin="$TEST_TMP/system-info-bin"
    local home="$TEST_TMP/system-info-home"
    mkdir -p "$bin" "$home"
    cat > "$bin/ip" <<'EOF'
#!/bin/bash
echo "simulated netlink denial" >&2
exit 1
EOF
    chmod +x "$bin/ip"
    HOME="$home" PATH="$bin:/usr/bin:/bin" /bin/bash "$REPO_ROOT/essentials/system-info.sh" \
        > "$TEST_TMP/system-info.out" 2>&1
    local report
    report=$(find "$home" -maxdepth 1 -name 'system-info-*.log' -print -quit)
    [ -n "$report" ] || fail "system-info did not produce a report"
    assert_contains "$report" "(network probe failed)"
    assert_contains "$report" "=== ENV ==="
}

test_flutter_scope_and_status() {
    local bin="$TEST_TMP/flutter-bin"
    local home="$TEST_TMP/flutter-home"
    local log="$TEST_TMP/flutter.log"
    local output="$TEST_TMP/flutter.out"
    mkdir -p "$bin" "$home/development" "$home"
    ln -s /usr/bin/dirname "$bin/dirname"
    ln -s /usr/bin/grep "$bin/grep"
    ln -s /usr/bin/mkdir "$bin/mkdir"
    cat > "$bin/sudo" <<'EOF'
#!/bin/bash
echo "sudo $*" >> "$STUB_LOG"
EOF
    cat > "$bin/git" <<'EOF'
#!/bin/bash
echo "git $*" >> "$STUB_LOG"
if [ "${1:-}" = clone ]; then
    mkdir -p "${@: -1}"
fi
EOF
    cat > "$bin/flutter" <<'EOF'
#!/bin/bash
echo "flutter $*" >> "$STUB_LOG"
if [ "${1:-}" = doctor ]; then exit 1; fi
EOF
    chmod +x "$bin/sudo" "$bin/git" "$bin/flutter"
    STUB_LOG="$log" HOME="$home" PATH="$bin:/usr/bin:/bin" \
        /bin/bash "$REPO_ROOT/dev/flutter.sh" > "$output" 2>&1
    if grep -qE 'add-architecture|:i386' "$log"; then
        fail "Flutter installer still mutates i386/Android prerequisites"
    fi
    assert_contains "$output" "Android SDK/license setup skipped"
    assert_contains "$output" "Flutter doctor reported incomplete optional tooling"
    assert_contains "$output" "Android status: not configured"
}

test_font_extraction() {
    local bin="$TEST_TMP/font-bin"
    local home="$TEST_TMP/font-home"
    local fixture="$TEST_TMP/font-fixture"
    local archive="$TEST_TMP/font.tar.xz"
    mkdir -p "$bin" "$home" "$fixture"
    printf 'font-data' > "$fixture/TestNerdFont.ttf"
    tar -cJf "$archive" -C "$fixture" TestNerdFont.ttf
    cat > "$bin/fc-cache" <<'EOF'
#!/bin/bash
exit 0
EOF
    cat > "$bin/fc-list" <<'EOF'
#!/bin/bash
exit 0
EOF
    cat > "$bin/curl" <<'EOF'
#!/bin/bash
# Models `curl -fsSLI -o /dev/null -w '%{url_effective}' <repo>/releases/latest`,
# which is how release tags are resolved now that api.github.com is avoided.
for arg in "$@"; do
    case "$arg" in
        */releases/latest) echo "${arg%/latest}/tag/v-test"; exit 0 ;;
    esac
done
echo '{"tag_name":"v-test"}'
EOF
    cat > "$bin/wget" <<'EOF'
#!/bin/bash
while [ "$#" -gt 0 ]; do
    if [ "$1" = -O ]; then
        shift
        cp "$FONT_ARCHIVE" "$1"
        exit 0
    fi
    shift
done
exit 2
EOF
    chmod +x "$bin/fc-cache" "$bin/fc-list" "$bin/curl" "$bin/wget"
    FONT_ARCHIVE="$archive" HOME="$home" PATH="$bin:/usr/bin:/bin" \
        /bin/bash "$REPO_ROOT/tools/fonts.sh" > "$TEST_TMP/fonts.out" 2>&1
    [ -s "$home/.local/share/fonts/TestNerdFont.ttf" ] || fail "font file was not installed"

    tar -cJf "$TEST_TMP/empty-font.tar.xz" -C "$fixture" --files-from /dev/null
    if FONT_ARCHIVE="$TEST_TMP/empty-font.tar.xz" HOME="$TEST_TMP/empty-font-home" \
        PATH="$bin:/usr/bin:/bin" /bin/bash "$REPO_ROOT/tools/fonts.sh" \
        > "$TEST_TMP/fonts-empty.out" 2>&1; then
        fail "font installer suppressed an archive with no font files"
    fi
}

test_prompt_runner_config() {
    local home="$TEST_TMP/prompt-home"
    local bin="$TEST_TMP/prompt-bin"
    local output="$TEST_TMP/prompt.out"
    mkdir -p "$home" "$bin"
    printf '%s\n' 'PROMPT_BACKEND=from-user-config' > "$home/.env-ubuntu-post-install"
    cat > "$bin/curl" <<'EOF'
#!/bin/bash
exit 99
EOF
    cat > "$bin/jq" <<'EOF'
#!/bin/bash
exit 99
EOF
    chmod +x "$bin/curl" "$bin/jq"

    HOME="$home" PATH="$bin:/usr/bin:/bin" /bin/bash "$REPO_ROOT/ai/prompt-runner.sh" \
        >/dev/null
    if printf 'test prompt\n' | HOME="$home" PATH="$bin:/usr/bin:/bin" \
        "$home/.local/bin/prompt" > "$output" 2>&1; then
        fail "generated prompt runner accepted an invalid configured backend"
    fi
    assert_contains "$output" "Unknown backend: from-user-config"
}

test_failed_remote_installer_is_not_executed() {
    local bin="$TEST_TMP/failed-installer-bin"
    local name script home output marker status
    mkdir -p "$bin"
    cat > "$bin/curl" <<'EOF'
#!/bin/bash
payload='printf "executed\n" > "$STUB_EXEC_MARKER"'
out=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        -o) out="$2"; shift 2 ;;
        *) shift ;;
    esac
done
if [ -n "$out" ]; then
    printf '%s\n' "$payload" > "$out"
else
    printf '%s\n' "$payload"
fi
exit 18
EOF
    chmod +x "$bin/curl"

    for entry in \
        "opencode:$REPO_ROOT/ai/opencode.sh" \
        "codex:$REPO_ROOT/ai/codex.sh" \
        "copilot:$REPO_ROOT/ai/github-copilot.sh" \
        "hf:$REPO_ROOT/ai/huggingface-cli.sh" \
        "aider:$REPO_ROOT/ai/aider.sh" \
        "goose:$REPO_ROOT/ai/goose.sh" \
        "qwen:$REPO_ROOT/ai/qwen-code.sh" \
        "cursor-agent:$REPO_ROOT/ai/cursor-agent.sh" \
        "vibe:$REPO_ROOT/ai/mistral-vibe.sh" \
        "fabric:$REPO_ROOT/ai/fabric.sh"; do
        IFS=: read -r name script <<< "$entry"
        home="$TEST_TMP/${name}-failed-home"
        output="$TEST_TMP/${name}-failed.out"
        marker="$TEST_TMP/${name}-executed"
        mkdir -p "$home"

        set +e
        STUB_EXEC_MARKER="$marker" HOME="$home" PATH="$bin:/usr/bin:/bin" \
            OPENCODE_INSTALL_DIR="$home/.opencode" /bin/bash "$script" > "$output" 2>&1
        status=$?
        set -e

        [ "$status" -ne 0 ] || fail "$name accepted a failed installer download"
        [ ! -e "$marker" ] || fail "$name executed content from a failed installer download"
    done
}

test_ollama_models() {
    local bin="$TEST_TMP/ollama-models-bin"
    local home="$TEST_TMP/ollama-models-home"
    local log="$TEST_TMP/ollama-models.log"
    local output="$TEST_TMP/ollama-models.out"
    local pull_count
    mkdir -p "$bin" "$home"
    cat > "$bin/ollama" <<'EOF'
#!/bin/bash
case "${1:-}" in
    list)
        printf 'NAME ID SIZE MODIFIED\nexisting:latest abc 1GB now\n'
        ;;
    pull)
        echo "pull $2 host=${OLLAMA_HOST:-}" >> "$STUB_LOG"
        ;;
    *) exit 2 ;;
esac
EOF
    chmod +x "$bin/ollama"

    STUB_LOG="$log" HOME="$home" OLLAMA_HOST="http://ollama.test:11434" \
        OLLAMA_MODELS=$'existing missing:7b\nmissing:7b' PATH="$bin:/usr/bin:/bin" \
        /bin/bash "$REPO_ROOT/ai/ollama-models.sh" > "$output" 2>&1
    assert_contains "$output" "existing already available"
    assert_contains "$log" "pull missing:7b host=http://ollama.test:11434"
    pull_count=$(grep -c '^pull missing:7b ' "$log")
    [ "$pull_count" -eq 1 ] || fail "Ollama model list did not deduplicate configured models"

    if STUB_LOG="$log" HOME="$home" OLLAMA_MODELS="" PATH="$bin:/usr/bin:/bin" \
        /bin/bash "$REPO_ROOT/ai/ollama-models.sh" > "$TEST_TMP/ollama-models-empty.out" 2>&1; then
        fail "Ollama model installer accepted an empty model list"
    fi
    assert_contains "$TEST_TMP/ollama-models-empty.out" "OLLAMA_MODELS is empty"
}

test_cli_tools_preserves_user_bat_and_configures_path() {
    local home="$TEST_TMP/cli-tools-home"
    local bin="$TEST_TMP/cli-tools-bin"
    local output="$TEST_TMP/cli-tools.out"
    local cmd rc marker_count
    mkdir -p "$home/.local/bin" "$bin"
    printf 'user-owned-bat\n' > "$home/.local/bin/bat"
    printf "   # \$HOME/.local/bin is intentionally not configured here\n" > "$home/.bashrc"
    printf "   # \$HOME/.local/bin is intentionally not configured here\n" > "$home/.zshrc"

    for cmd in batcat fzf rg jq htop tmux tree eza gh; do
        ln -s /usr/bin/true "$bin/$cmd"
    done
    cat > "$bin/sudo" <<'EOF'
#!/bin/bash
exit 0
EOF
    chmod +x "$bin/sudo"

    HOME="$home" PATH="$bin:/usr/bin:/bin" \
        /bin/bash "$REPO_ROOT/tools/cli-tools.sh" > "$output" 2>&1
    HOME="$home" PATH="$bin:/usr/bin:/bin" \
        /bin/bash "$REPO_ROOT/tools/cli-tools.sh" >> "$output" 2>&1

    [ ! -L "$home/.local/bin/bat" ] || fail "cli-tools replaced an unmanaged bat file"
    [ "$(< "$home/.local/bin/bat")" = "user-owned-bat" ] \
        || fail "cli-tools changed an unmanaged bat file"
    for rc in "$home/.bashrc" "$home/.zshrc"; do
        assert_contains "$rc" "export PATH=\"\$HOME/.local/bin:\$PATH\""
        marker_count=$(grep -cF '# ~/.local/bin (added by cli-tools.sh)' "$rc")
        [ "$marker_count" -eq 1 ] || fail "cli-tools PATH block was not idempotent in $rc"
    done
}

test_modern_cli_requires_checksum() {
    local home="$TEST_TMP/modern-checksum-home"
    local bin="$TEST_TMP/modern-checksum-bin"
    local log="$TEST_TMP/modern-checksum.log"
    local output="$TEST_TMP/modern-checksum.out"
    local cmd status
    mkdir -p "$home" "$bin"

    for cmd in btop direnv hyperfine delta fdfind lazygit zoxide dust; do
        ln -s /usr/bin/true "$bin/$cmd"
    done
    cat > "$bin/sudo" <<'EOF'
#!/bin/bash
echo "$*" >> "$STUB_LOG"
exit 0
EOF
    cat > "$bin/curl" <<'EOF'
#!/bin/bash
url=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        -o|-w) shift 2 ;;
        -*) shift ;;
        *) url="$1"; shift ;;
    esac
done
case "$url" in
    */releases/latest)
        printf '%s\n' "${url%/latest}/tag/v1.8.1"
        exit 0
        ;;
    *.sha256) exit 22 ;;
    *) exit 2 ;;
esac
EOF
    cat > "$bin/wget" <<'EOF'
#!/bin/bash
out=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        -O) out="$2"; shift 2 ;;
        *) shift ;;
    esac
done
[ -n "$out" ] || exit 2
printf 'downloaded-binary\n' > "$out"
EOF
    chmod +x "$bin/sudo" "$bin/curl" "$bin/wget"

    set +e
    STUB_LOG="$log" HOME="$home" PATH="$bin:/usr/bin:/bin" \
        /bin/bash "$REPO_ROOT/tools/modern-cli.sh" > "$output" 2>&1
    status=$?
    set -e

    [ "$status" -ne 0 ] || fail "modern-cli accepted a missing tealdeer checksum"
    if grep -q 'install .*tldr' "$log"; then
        fail "modern-cli installed tealdeer after checksum retrieval failed"
    fi
}

test_npm_installers
test_remote_ai_installers
test_pipx_ai_installers
test_claude_apt_installer
test_architecture_guards
test_system_info_optional_failure
test_flutter_scope_and_status
test_font_extraction
test_prompt_runner_config
test_failed_remote_installer_is_not_executed
test_ollama_models
test_cli_tools_preserves_user_bat_and_configures_path
test_modern_cli_requires_checksum

echo "✅ Installer regression tests passed"
