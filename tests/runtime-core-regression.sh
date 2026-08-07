#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*" >&2; exit 1; }
assert_contains() {
    local haystack="$1" needle="$2"
    [[ "$haystack" == *"$needle"* ]] || fail "expected output to contain: $needle"
}

test_setup_summary() {
    local root="$TEST_ROOT/setup" home="$TEST_ROOT/setup/home" fakebin="$TEST_ROOT/setup/bin"
    mkdir -p "$home/.cache/ubuntu-setup" "$fakebin"
    touch "$home/.cache/ubuntu-setup/essentials_auto-updates.sh.done"
    cat > "$fakebin/clear" <<'EOF'
#!/bin/bash
exit 0
EOF
    cat > "$fakebin/bash" <<'EOF'
#!/bin/bash
case "$1" in
    */essentials/swap.sh) exit 0 ;;
    */essentials/firewall.sh) exit 1 ;;
    *) exit 99 ;;
esac
EOF
    chmod +x "$fakebin/clear" "$fakebin/bash"

    local output status
    set +e
    output=$(printf '\n1 2 3\n\n\n\n\n\n\n\n\ny\n' | HOME="$home" PATH="$fakebin:$PATH" \
        SETUP_LOG_FILE="$root/setup.log" /bin/bash "$REPO_ROOT/setup.sh" 2>&1)
    status=$?
    set -e
    [ "$status" -eq 1 ] || fail "setup mixed-result run should exit 1"
    assert_contains "$output" "1 succeeded"
    assert_contains "$output" "1 failed"
    assert_contains "$output" "1 skipped"
    pass "setup summary counts success, failure, and skipped under set -e"
}

test_backup_cleanup() {
    local home="$TEST_ROOT/backup/home" fakebin="$TEST_ROOT/backup/bin" output status
    mkdir -p "$home/.ssh" "$home/backups" "$fakebin"
    printf 'secret\n' > "$home/.ssh/id_test"
    cat > "$fakebin/gpg" <<'EOF'
#!/bin/bash
exit 1
EOF
    chmod +x "$fakebin/gpg"
    set +e
    output=$(HOME="$home" PATH="$fakebin:$PATH" BACKUP_DIR="$home/backups" \
        BACKUP_ENCRYPT=yes BACKUP_GPG_RECIPIENT=test@example.com \
        /bin/bash "$REPO_ROOT/tools/backup-home.sh" 2>&1)
    status=$?
    set -e
    [ "$status" -ne 0 ] || fail "backup should fail when encryption fails"
    [ -z "$(find "$home/backups" -type f -print -quit)" ] || fail "backup left plaintext or partial encrypted output"
    pass "encrypted backup failure removes plaintext and partial output"
}

make_wget_mock() {
    local target="$1"
    cat > "$target" <<'EOF'
#!/bin/bash
out=""
source_file=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        -O) out="$2"; shift 2 ;;
        -*) shift ;;
        *) source_file="${1#file://}"; shift ;;
    esac
done
cp "$source_file" "$out"
EOF
    chmod +x "$target"
}

test_go_install() {
    local root="$TEST_ROOT/go" home="$TEST_ROOT/go/home" fakebin="$TEST_ROOT/go/bin"
    local archive="$TEST_ROOT/go/go.tar.gz" checksum target output status
    mkdir -p "$home/sdk/go-incomplete" "$root/archive/go/bin" "$fakebin"
    set +e
    output=$(HOME="$home" GO_INSTALL_DIR="$home/sdk/go-incomplete" \
        /bin/bash "$REPO_ROOT/dev/go.sh" 2>&1)
    status=$?
    set -e
    [ "$status" -ne 0 ] || fail "incomplete Go directory should be rejected"
    assert_contains "$output" "not a complete Go installation"

    cat > "$root/archive/go/bin/go" <<'EOF'
#!/bin/bash
echo 'go version go9.9 linux/test'
EOF
    chmod +x "$root/archive/go/bin/go"
    tar -C "$root/archive" -czf "$archive" go
    checksum=$(sha256sum "$archive" | awk '{print $1}')
    make_wget_mock "$fakebin/wget"
    target="$home/sdk/go-custom"
    set +e
    output=$(HOME="$home" PATH="$fakebin:$PATH" GO_INSTALL_DIR="$target" GO_VERSION=go9.9 \
        GO_ARCHIVE_URL="file://$archive" /bin/bash "$REPO_ROOT/dev/go.sh" 2>&1)
    status=$?
    set -e
    [ "$status" -ne 0 ] || fail "custom Go archive without a checksum should fail"
    assert_contains "$output" "refusing an unverified Go archive"

    HOME="$home" PATH="$fakebin:$PATH" GO_INSTALL_DIR="$target" GO_VERSION=go9.9 \
        GO_ARCHIVE_URL="file://$archive" GO_ARCHIVE_SHA256="$checksum" \
        /bin/bash "$REPO_ROOT/dev/go.sh" >/dev/null
    [ -x "$target/bin/go" ] || fail "Go was not installed at custom target"
    [ ! -e /usr/local/go/bin/go9.9-regression ] || fail "Go test unexpectedly touched /usr/local"
    pass "Go rejects incomplete installs and honors a custom verified archive target"
}

test_nvim_safety_and_rollback() {
    local root="$TEST_ROOT/nvim" home="$TEST_ROOT/nvim/home" fakebin="$TEST_ROOT/nvim/bin"
    local good="$root/good.tar.gz" bad="$root/bad.tar.gz" checksum target status outside="$root/outside"
    mkdir -p "$home" "$outside" "$root/good/nvim-linux-x86_64/bin" "$root/bad/nvim-linux-x86_64/bin" "$fakebin"
    make_wget_mock "$fakebin/wget"

    local unsafe_target
    ln -s "$outside" "$home/escape"
    for unsafe_target in "/" "$home" "$home/nvim" "$home/apps/editor" \
        "$home/.config/nvim" "$home/.ssh/nvim" "$home/.gnupg/nvim" \
        "$home/.local/bin/nvim" "$home/escape/nvim-test"; do
        set +e
        HOME="$home" PATH="$fakebin:$PATH" NVIM_INSTALL_DIR="$unsafe_target" NVIM_VERSION=vtest \
            NVIM_ARCHIVE_URL=file:///unused /bin/bash "$REPO_ROOT/ide/nvim.sh" >/dev/null 2>&1
        status=$?
        set -e
        [ "$status" -ne 0 ] || fail "unsafe Neovim target should be rejected: $unsafe_target"
    done

    mkdir -p "$home/Documents/nvim"
    printf 'unrelated data\n' > "$home/Documents/nvim/notes.txt"
    set +e
    HOME="$home" PATH="$fakebin:$PATH" NVIM_INSTALL_DIR="$home/Documents/nvim" NVIM_VERSION=vtest \
        NVIM_ARCHIVE_URL=file:///unused /bin/bash "$REPO_ROOT/ide/nvim.sh" >/dev/null 2>&1
    status=$?
    set -e
    [ "$status" -ne 0 ] || fail "unmanaged existing Neovim-named directory should be rejected"
    [ -f "$home/Documents/nvim/notes.txt" ] || fail "unmanaged existing directory was modified"

    cat > "$root/good/nvim-linux-x86_64/bin/nvim" <<'EOF'
#!/bin/bash
echo 'NVIM vtest'
EOF
    cat > "$root/bad/nvim-linux-x86_64/bin/nvim" <<'EOF'
#!/bin/bash
exit 1
EOF
    chmod +x "$root/good/nvim-linux-x86_64/bin/nvim" "$root/bad/nvim-linux-x86_64/bin/nvim"
    tar -C "$root/good" -czf "$good" nvim-linux-x86_64
    tar -C "$root/bad" -czf "$bad" nvim-linux-x86_64
    checksum=$(sha256sum "$good" | awk '{print $1}')
    target="$home/apps/nvim-test"
    set +e
    HOME="$home" PATH="$fakebin:$PATH" NVIM_INSTALL_DIR="$target" NVIM_VERSION=vtest \
        NVIM_ARCHIVE_URL="file://$good" /bin/bash "$REPO_ROOT/ide/nvim.sh" >/dev/null 2>&1
    status=$?
    set -e
    [ "$status" -ne 0 ] || fail "custom Neovim archive without a checksum should fail"

    HOME="$home" PATH="$fakebin:$PATH" NVIM_INSTALL_DIR="$target" NVIM_VERSION=vtest \
        NVIM_ARCHIVE_URL="file://$good" NVIM_ARCHIVE_SHA256="$checksum" \
        /bin/bash "$REPO_ROOT/ide/nvim.sh" >/dev/null
    [ -x "$target/bin/nvim" ] || fail "Neovim valid staged install failed"
    printf 'preserve\n' > "$target/sentinel"

    set +e
    HOME="$home" PATH="$fakebin:$PATH" NVIM_INSTALL_DIR="$target" NVIM_VERSION=vtest \
        NVIM_ARCHIVE_URL="file://$bad" NVIM_ARCHIVE_SHA256="$(sha256sum "$bad" | awk '{print $1}')" \
        /bin/bash "$REPO_ROOT/ide/nvim.sh" >/dev/null 2>&1
    status=$?
    set -e
    [ "$status" -ne 0 ] || fail "invalid Neovim archive should fail validation"
    [ "$(cat "$target/sentinel")" = preserve ] || fail "failed Neovim replacement damaged existing install"

    cat > "$fakebin/mv" <<'EOF'
#!/bin/bash
if [[ "$1" == */.nvim-stage.* && "$2" == "$NVIM_MV_FAIL_TARGET" ]]; then
    exit 1
fi
exec /bin/mv "$@"
EOF
    chmod +x "$fakebin/mv"
    set +e
    HOME="$home" PATH="$fakebin:$PATH" NVIM_MV_FAIL_TARGET="$target" \
        NVIM_INSTALL_DIR="$target" NVIM_VERSION=vtest NVIM_ARCHIVE_URL="file://$good" \
        NVIM_ARCHIVE_SHA256="$checksum" /bin/bash "$REPO_ROOT/ide/nvim.sh" >/dev/null 2>&1
    status=$?
    set -e
    [ "$status" -ne 0 ] || fail "simulated Neovim replacement failure should fail"
    [ "$(cat "$target/sentinel")" = preserve ] || fail "Neovim replacement failure did not restore the old install"
    [ -x "$target/bin/nvim" ] || fail "Neovim replacement failure lost the old executable"
    pass "Neovim rejects unsafe targets and validates before replacing"
}

test_swap_persistence() {
    local root="$TEST_ROOT/swap" fakebin="$TEST_ROOT/swap/bin" swapfile="$TEST_ROOT/swap/swapfile"
    local fstab="$TEST_ROOT/swap/fstab" calls="$TEST_ROOT/swap/swapon.calls"
    mkdir -p "$fakebin"
    touch "$swapfile" "$fstab" "$calls"
    cat > "$fakebin/swapon" <<'EOF'
#!/bin/bash
if [ "${1:-}" = "--show" ]; then exit 0; fi
echo "$*" >> "$SWAPON_CALLS"
EOF
    cat > "$fakebin/sudo" <<'EOF'
#!/bin/bash
exec "$@"
EOF
    chmod +x "$fakebin/swapon" "$fakebin/sudo"
    HOME="$TEST_ROOT/swap/home" PATH="$fakebin:$PATH" SWAP_FILE="$swapfile" FSTAB_FILE="$fstab" \
        SWAPON_CALLS="$calls" /bin/bash "$REPO_ROOT/essentials/swap.sh" >/dev/null
    grep -qF "$swapfile" "$calls" || fail "existing inactive swap was not enabled"
    grep -qF "$swapfile none swap sw 0 0" "$fstab" || fail "existing inactive swap was not persisted"
    pass "existing inactive swap reaches persistence logic"
}

test_gpg_selection() {
    local root="$TEST_ROOT/gpg" home="$TEST_ROOT/gpg/home" fakebin="$TEST_ROOT/gpg/bin"
    local output status git_log="$TEST_ROOT/gpg/git.log" gpg_log="$TEST_ROOT/gpg/gpg.log"
    mkdir -p "$home" "$fakebin"
    cat > "$fakebin/gpg" <<'EOF'
#!/bin/bash
echo "$*" >> "${GPG_CALL_LOG:-/dev/null}"
case " $* " in
    *" --list-secret-keys "*)
        if [ "${GPG_MOCK_FAIL:-}" = yes ]; then
            echo 'simulated keyring failure' >&2
            exit 2
        elif [ "${GPG_MOCK_UNIQUE:-}" = yes ]; then
            printf 'sec:::::::::\nfpr:::::::::AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA:\n'
            printf 'uid:u::::1700000000::HASH::Test User <unique@example.com>::::::::::0:\n'
        else
            printf 'sec:::::::::\nfpr:::::::::AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA:\n'
            printf 'uid:u::::1700000000::HASH::Test User <test@example.com>::::::::::0:\n'
            printf 'sec:::::::::\nfpr:::::::::BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB:\n'
            printf 'uid:u::::1700000000::HASH::Other User <test@example.com>::::::::::0:\n'
        fi
        ;;
    *" --export "*) echo PUBLIC ;;
esac
EOF
    cat > "$fakebin/git" <<'EOF'
#!/bin/bash
echo "$*" >> "$GIT_LOG"
EOF
    chmod +x "$fakebin/gpg" "$fakebin/git"
    set +e
    output=$(HOME="$home" PATH="$fakebin:$PATH" GIT_NAME=Test GIT_EMAIL=test@example.com \
        GIT_LOG="$git_log" GPG_CALL_LOG="$gpg_log" /bin/bash "$REPO_ROOT/system/gpg.sh" 2>&1)
    status=$?
    set -e
    [ "$status" -ne 0 ] || fail "ambiguous email key selection should fail"
    assert_contains "$output" "Multiple secret keys match"

    HOME="$home" PATH="$fakebin:$PATH" GIT_EMAIL=unique@example.com GPG_MOCK_UNIQUE=yes \
        GIT_LOG="$git_log" GPG_CALL_LOG="$gpg_log" /bin/bash "$REPO_ROOT/system/gpg.sh" >/dev/null
    grep -qF 'config --global user.signingkey AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA' "$git_log" \
        || fail "unique configured-email GPG key was not configured"

    HOME="$home" PATH="$fakebin:$PATH" GPG_KEY_ID=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA \
        GIT_LOG="$git_log" GPG_CALL_LOG="$gpg_log" \
        /bin/bash "$REPO_ROOT/system/gpg.sh" >/dev/null
    grep -qF 'config --global user.signingkey AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA' "$git_log" \
        || fail "explicit GPG key was not configured"

    : > "$git_log"
    : > "$gpg_log"
    set +e
    output=$(HOME="$home" PATH="$fakebin:$PATH" GIT_EMAIL=unique@example.com GPG_MOCK_FAIL=yes \
        GIT_LOG="$git_log" GPG_CALL_LOG="$gpg_log" /bin/bash "$REPO_ROOT/system/gpg.sh" 2>&1)
    status=$?
    set -e
    [ "$status" -ne 0 ] || fail "GPG keyring lookup failure should abort"
    assert_contains "$output" "Could not read the GPG secret-key inventory"
    ! grep -q -- '--generate-key' "$gpg_log" || fail "GPG lookup failure triggered key generation"
    [ ! -s "$git_log" ] || fail "GPG lookup failure changed git configuration"
    pass "GPG requires an explicit key or a unique configured-email match"
}

test_setup_summary
test_backup_cleanup
test_go_install
test_nvim_safety_and_rollback
test_swap_persistence
test_gpg_selection
echo "All runtime core regressions passed."
