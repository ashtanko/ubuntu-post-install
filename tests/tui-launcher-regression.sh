#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT

fail() {
    echo "❌ $*" >&2
    exit 1
}

HOME_DIR="$TEST_ROOT/home"
FAKE_BIN="$TEST_ROOT/bin"
mkdir -p "$HOME_DIR" "$FAKE_BIN"

cat > "$FAKE_BIN/bash" <<'EOF'
#!/bin/bash
case "${1:-}" in
    */essentials/system-info.sh)
        echo "stub system info"
        exit 0
        ;;
    */essentials/swap.sh)
        echo "stub swap failure" >&2
        exit 1
        ;;
    *) exec /bin/bash "$@" ;;
esac
EOF
chmod +x "$FAKE_BIN/bash"

HOME="$HOME_DIR" PATH="$FAKE_BIN:$PATH" SETUP_LOG_FILE="$TEST_ROOT/setup.log" \
    /bin/bash "$REPO_ROOT/setup.sh" --run-item essentials/system-info.sh >/dev/null
[ -f "$HOME_DIR/.cache/ubuntu-setup/essentials_system-info.sh.done" ] \
    || fail "successful TUI runner item did not create its marker"

# A completed item must skip without invoking the now-failing child stub.
cat > "$FAKE_BIN/bash" <<'EOF'
#!/bin/bash
case "${1:-}" in
    */essentials/system-info.sh) exit 99 ;;
    */essentials/swap.sh) exit 1 ;;
    *) exec /bin/bash "$@" ;;
esac
EOF
chmod +x "$FAKE_BIN/bash"
HOME="$HOME_DIR" PATH="$FAKE_BIN:$PATH" SETUP_LOG_FILE="$TEST_ROOT/setup.log" \
    /bin/bash "$REPO_ROOT/setup.sh" --run-item essentials/system-info.sh >/dev/null

set +e
HOME="$HOME_DIR" PATH="$FAKE_BIN:$PATH" SETUP_LOG_FILE="$TEST_ROOT/setup.log" \
    /bin/bash "$REPO_ROOT/setup.sh" --run-item essentials/swap.sh >/dev/null 2>&1
failure_status=$?
HOME="$HOME_DIR" PATH="$FAKE_BIN:$PATH" SETUP_LOG_FILE="$TEST_ROOT/setup.log" \
    /bin/bash "$REPO_ROOT/setup.sh" --run-item does/not-exist.sh >/dev/null 2>&1
unknown_status=$?
set -e

[ "$failure_status" -eq 1 ] || fail "failed TUI runner item returned $failure_status instead of 1"
[ ! -f "$HOME_DIR/.cache/ubuntu-setup/essentials_swap.sh.done" ] \
    || fail "failed TUI runner item created a completion marker"
[ "$unknown_status" -eq 2 ] || fail "unknown TUI runner item returned $unknown_status instead of 2"

echo "✅ TUI launcher validates catalog items, failures, skips, and markers"
