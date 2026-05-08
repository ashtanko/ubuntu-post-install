#!/bin/bash
# Run inside the test container. Executes one script per invocation, then
# verifies it. In `idempotency` mode, runs twice and diffs state.
set -uo pipefail

if [ -z "${BASH_VERSION:-}" ]; then
    exec /bin/bash "$0" "$@"
fi

SCRIPT_PATH="${MANIFEST_SCRIPT:?MANIFEST_SCRIPT required}"
ENV_PAIRS="${MANIFEST_ENV:-}"
VERIFY_CMD="${MANIFEST_VERIFY:-}"
MODE="${MANIFEST_MODE:-smoke}"

# Stage repo into a writable location (container mount may be read-only)
WORK="$HOME/work"
rm -rf "$WORK"
cp -r /home/tester/repo "$WORK"
cd "$WORK"

# Drop in CI .env (overrides anything in tests/fixtures)
cp tests/fixtures/test.env .env

# Build env-pair args for `env`
declare -a ENV_ARGS=()
if [ -n "$ENV_PAIRS" ]; then
    IFS=',' read -ra pairs <<<"$ENV_PAIRS"
    for kv in "${pairs[@]}"; do
        # Allow $HOME-style expansion in manifest values
        kv_expanded=$(eval echo "$kv")
        ENV_ARGS+=("$kv_expanded")
    done
fi

run_script() {
    local label="$1" log="$2"
    echo "▶️  [$label] $SCRIPT_PATH"
    if [ "${#ENV_ARGS[@]}" -gt 0 ]; then
        env "${ENV_ARGS[@]}" bash "$SCRIPT_PATH" 2>&1 | tee "$log"
    else
        bash "$SCRIPT_PATH" 2>&1 | tee "$log"
    fi
    return "${PIPESTATUS[0]}"
}

run_verify() {
    if [ -z "$VERIFY_CMD" ]; then
        return 0
    fi
    local file_verify
    if [ "$VERIFY_CMD" = "FILE" ]; then
        file_verify="$WORK/tests/verify/$(echo "$SCRIPT_PATH" | tr '/' '_')"
        if [ ! -f "$file_verify" ]; then
            echo "❌ verify=FILE but $file_verify does not exist"
            return 1
        fi
        bash "$file_verify"
    else
        bash -c "$VERIFY_CMD"
    fi
}

snapshot() {
    local out="$1"
    {
        echo "## dpkg"
        dpkg-query -W -f='${Package} ${Version}\n' 2>/dev/null | sort
        echo "## bashrc-bytes"
        wc -c "$HOME/.bashrc" 2>/dev/null || true
        echo "## zshrc-bytes"
        wc -c "$HOME/.zshrc" 2>/dev/null || true
        echo "## profile-bytes"
        wc -c "$HOME/.profile" 2>/dev/null || true
        echo "## local-bin"
        ls -1 "$HOME/.local/bin" 2>/dev/null | sort
    } > "$out"
}

LOG1=/tmp/run1.log
LOG2=/tmp/run2.log
SNAP1=/tmp/snap1.txt
SNAP2=/tmp/snap2.txt

if ! run_script "run-1" "$LOG1"; then
    echo "❌ FIRST RUN FAILED: $SCRIPT_PATH"
    exit 1
fi

if ! run_verify; then
    echo "❌ VERIFY FAILED: $SCRIPT_PATH"
    exit 1
fi

if [ "$MODE" = "smoke" ]; then
    echo "✅ SMOKE OK: $SCRIPT_PATH"
    exit 0
fi

# idempotency mode
snapshot "$SNAP1"

if ! run_script "run-2" "$LOG2"; then
    echo "❌ SECOND RUN FAILED (idempotency): $SCRIPT_PATH"
    exit 1
fi

snapshot "$SNAP2"

if ! diff -u "$SNAP1" "$SNAP2"; then
    echo "❌ STATE CHANGED ON RE-RUN: $SCRIPT_PATH"
    exit 1
fi

echo "✅ IDEMPOTENCY OK: $SCRIPT_PATH"
