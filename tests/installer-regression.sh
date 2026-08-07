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
echo v20.0.0
EOF
    cat > "$bin/npm" <<'EOF'
#!/bin/bash
echo "$0 $*" >> "$STUB_LOG"
if [ "${1:-}" = config ]; then
    echo "$NPM_PREFIX"
    exit 0
fi
case "$*" in
    *anthropic-ai*) target=claude ;;
    *google/gemini-cli*) target=gemini ;;
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
    local name script package bin prefix log output
    for entry in \
        "claude:$REPO_ROOT/tools/claude.sh:@anthropic-ai/claude-code" \
        "gemini:$REPO_ROOT/ai/gemini.sh:@google/gemini-cli"; do
        IFS=: read -r name script package <<< "$entry"

        bin="$TEST_TMP/${name}-user-bin"
        prefix="$TEST_TMP/home/.local/${name}-prefix"
        log="$TEST_TMP/${name}-user.log"
        output="$TEST_TMP/${name}-user.out"
        mkdir -p "$TEST_TMP/home"
        make_npm_stubs "$bin"
        STUB_BIN="$bin" STUB_LOG="$log" NPM_PREFIX="$prefix" HOME="$TEST_TMP/home" \
            PATH="$bin" /bin/bash "$script" > "$output" 2>&1
        assert_contains "$log" "$bin/npm install -g $package"
        if grep -q '^sudo ' "$log"; then
            fail "$name used sudo for a writable user prefix"
        fi

        bin="$TEST_TMP/${name}-system-bin"
        log="$TEST_TMP/${name}-system.log"
        output="$TEST_TMP/${name}-system.out"
        make_npm_stubs "$bin"
        STUB_BIN="$bin" STUB_LOG="$log" NPM_PREFIX="/proc/installer-prefix" HOME="$TEST_TMP/home" \
            PATH="$bin" /bin/bash "$script" > "$output" 2>&1
        assert_contains "$log" "sudo $bin/npm install -g $package"
    done

    local missing_bin="$TEST_TMP/npm-missing-bin"
    mkdir -p "$missing_bin"
    ln -s /usr/bin/cut "$missing_bin/cut"
    ln -s /usr/bin/dirname "$missing_bin/dirname"
    cat > "$missing_bin/node" <<'EOF'
#!/bin/bash
echo v20.0.0
EOF
    chmod +x "$missing_bin/node"
    if HOME="$TEST_TMP/home" PATH="$missing_bin" /bin/bash "$REPO_ROOT/tools/claude.sh" \
        > "$TEST_TMP/npm-missing.out" 2>&1; then
        fail "Claude installer accepted Node.js without npm"
    fi
    assert_contains "$TEST_TMP/npm-missing.out" "npm is required"
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

test_npm_installers
test_architecture_guards
test_system_info_optional_failure
test_flutter_scope_and_status
test_font_extraction
test_prompt_runner_config

echo "✅ Installer regression tests passed"
