#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/idempotency-lib.bash
source "$REPO_ROOT/tests/idempotency-lib.bash"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
mkdir -p "$HOME/.local/bin" "$HOME/owned-state"
# Keep the HOME token literal so the same expansion path as the manifest is used.
# shellcheck disable=SC2016
STATE_PATHS='$HOME/owned-state'

printf 'aaaa\n' > "$HOME/owned-state/content"
printf 'target-a\n' > "$HOME/owned-state/target-a"
printf 'target-b\n' > "$HOME/owned-state/target-b"
ln -s target-a "$HOME/owned-state/link"
snapshot_state "$TMP/before"

# Same-size content, mode-only, and symlink-target changes must all be visible.
printf 'bbbb\n' > "$HOME/owned-state/content"
chmod 600 "$HOME/owned-state/target-a"
ln -sfn target-b "$HOME/owned-state/link"
snapshot_state "$TMP/after"
if cmp -s "$TMP/before" "$TMP/after"; then
    echo "❌ idempotency snapshot missed deterministic state mutations"
    exit 1
fi
grep -q 'target-b' "$TMP/after" || { echo "❌ symlink target was not captured"; exit 1; }
grep -q '|600|' "$TMP/after" || { echo "❌ file mode was not captured"; exit 1; }

# shellcheck disable=SC2016
STATE_PATHS='$HOME/owned-state/../escape'
if snapshot_state "$TMP/unsafe" 2>/dev/null; then
    echo "❌ unsafe state path was accepted"
    exit 1
fi

mkdir -p "$TMP/failing-bin"
cat > "$TMP/failing-bin/find" <<'EOF'
#!/bin/bash
if [[ "${2:-}" == "${FIND_FAIL_PATH:-}" ]]; then
    echo 'simulated traversal failure' >&2
    exit 2
fi
exec /usr/bin/find "$@"
EOF
cat > "$TMP/failing-bin/dpkg-query" <<'EOF'
#!/bin/bash
if [[ "${DPKG_QUERY_FAIL:-}" == yes ]]; then
    echo 'simulated package-query failure' >&2
    exit 2
fi
exec /usr/bin/dpkg-query "$@"
EOF
cat > "$TMP/failing-bin/sort" <<'EOF'
#!/bin/bash
if [[ "${SORT_FAIL:-}" == yes ]]; then exit 2; fi
exec /usr/bin/sort "$@"
EOF
cat > "$TMP/failing-bin/stat" <<'EOF'
#!/bin/bash
if [[ "${*: -1}" == "${STAT_FAIL_PATH:-}" ]]; then exit 2; fi
exec /usr/bin/stat "$@"
EOF
cat > "$TMP/failing-bin/sha256sum" <<'EOF'
#!/bin/bash
if [[ "${*: -1}" == "${SHA_FAIL_PATH:-}" ]]; then exit 2; fi
exec /usr/bin/sha256sum "$@"
EOF
cat > "$TMP/failing-bin/readlink" <<'EOF'
#!/bin/bash
if [[ "${*: -1}" == "${READLINK_FAIL_PATH:-}" ]]; then exit 2; fi
exec /usr/bin/readlink "$@"
EOF
chmod +x "$TMP/failing-bin/"*

# shellcheck disable=SC2016
STATE_PATHS='$HOME/owned-state'
export FIND_FAIL_PATH="$HOME/owned-state"
if PATH="$TMP/failing-bin:$PATH" snapshot_state "$TMP/unreadable" 2>/dev/null; then
    echo "❌ tracked-state traversal failure was ignored"
    exit 1
fi
unset FIND_FAIL_PATH
if DPKG_QUERY_FAIL=yes PATH="$TMP/failing-bin:$PATH" snapshot_state "$TMP/no-packages" 2>/dev/null; then
    echo "❌ package-query failure was ignored"
    exit 1
fi
if SORT_FAIL=yes PATH="$TMP/failing-bin:$PATH" snapshot_state "$TMP/no-sort" 2>/dev/null; then
    echo "❌ package-state sort failure was ignored"
    exit 1
fi
if STAT_FAIL_PATH="$HOME/owned-state/content" PATH="$TMP/failing-bin:$PATH" \
    snapshot_state "$TMP/no-stat" 2>/dev/null; then
    echo "❌ tracked-state stat failure was ignored"
    exit 1
fi
if SHA_FAIL_PATH="$HOME/owned-state/content" PATH="$TMP/failing-bin:$PATH" \
    snapshot_state "$TMP/no-hash" 2>/dev/null; then
    echo "❌ tracked-state hash failure was ignored"
    exit 1
fi
if READLINK_FAIL_PATH="$HOME/owned-state/link" PATH="$TMP/failing-bin:$PATH" \
    snapshot_state "$TMP/no-readlink" 2>/dev/null; then
    echo "❌ tracked-state symlink failure was ignored"
    exit 1
fi

echo "✅ idempotency snapshot regression checks passed"
